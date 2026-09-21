package main

import (
	"context"
	"errors"
	"sync"
	"time"
)

// Operation contexts cross the ABI by ID, never by pointer. A command has a
// child context so cancelling one concurrent read does not cancel its siblings.
type nativeOperation struct {
	ctx        context.Context
	cancel     context.CancelFunc
	revoke     context.CancelCauseFunc
	owner      *nativeOperation
	mu         sync.Mutex
	proxy      *proxyListener
	generation uint64
}

var operations = struct {
	sync.Mutex
	next   uint64
	active map[uint64]*nativeOperation
}{active: make(map[uint64]*nativeOperation)}

func beginOperation(timeout time.Duration, ownsProxy bool, parent uint64) uint64 {
	operations.Lock()
	defer operations.Unlock()
	ctx := context.Background()
	var owner *nativeOperation
	if parent != 0 {
		if op := operations.active[parent]; op != nil {
			ctx, owner = op.ctx, op.owner
		} else {
			var cancel context.CancelFunc
			ctx, cancel = context.WithCancel(ctx)
			cancel() // A finished attempt must never produce an independent request.
		}
	}
	deadlineContext, cancel := context.WithTimeout(ctx, timeout)
	ctx, revoke := context.WithCancelCause(deadlineContext)
	op := &nativeOperation{ctx: ctx, cancel: func() { revoke(context.Canceled); cancel() }, revoke: revoke, owner: owner}
	if ownsProxy {
		op.owner = op
	}
	operations.next++
	operations.active[operations.next] = op
	return operations.next
}

func operationForID(id uint64) *nativeOperation {
	operations.Lock()
	defer operations.Unlock()
	return operations.active[id]
}

func cancelOperation(id uint64) {
	if op := operationForID(id); op != nil {
		op.cancel()
	}
}

func endOperation(id uint64) {
	operations.Lock()
	op := operations.active[id]
	delete(operations.active, id)
	operations.Unlock()
	if op != nil {
		op.cancel()
		op.mu.Lock()
		defer op.mu.Unlock()
		if op.proxy != nil {
			op.proxy.Close()
		}
	}
}

func cancelConnectionOperations(reason error) {
	operations.Lock()
	defer operations.Unlock()
	for _, op := range operations.active {
		if op.owner == op {
			op.revoke(reason)
		}
	}
}

func (op *nativeOperation) connectionProxy(generation uint64, makeProxy func(context.Context) (*proxyListener, error)) (*proxyListener, error) {
	owner := op.owner
	if owner == nil {
		return nil, errors.New("missing connection operation")
	}
	owner.mu.Lock()
	defer owner.mu.Unlock()
	if err := owner.ctx.Err(); err != nil {
		return nil, err
	}
	if owner.proxy != nil && owner.generation != generation {
		owner.proxy.Close()
		owner.proxy = nil
	}
	if owner.proxy == nil {
		proxy, err := makeProxy(owner.ctx)
		if err != nil {
			return nil, err
		}
		owner.proxy, owner.generation = proxy, generation
	}
	return owner.proxy, nil
}

var errSignedOut = errors.New("signed out")
var errConnectionChanged = errors.New("connection changed")

func nativeFailure(op *nativeOperation) snapshot {
	code := "unavailable"
	switch {
	case errors.Is(context.Cause(op.ctx), errSignedOut):
		code = "signed_out"
	case errors.Is(context.Cause(op.ctx), errConnectionChanged):
		code = "connection_changed"
	case errors.Is(op.ctx.Err(), context.DeadlineExceeded):
		code = "timeout"
	case errors.Is(op.ctx.Err(), context.Canceled):
		code = "cancelled"
	}
	return snapshot{State: "Error", Error: "Tailscale operation ended", ErrorCode: code}
}
