#lang racket

(require "node.rkt")
(require json)

(parameterize
    ([current-custodian (make-custodian)])

  (define routing-table
    (hash 0 8880
          1 8881
          2 8882
          3 8883
          4 8884))

  (define-values (in0 out0) (make-pipe))
  (define-values (in1 out1) (make-pipe))
  (define-values (in2 out2) (make-pipe))
  (define-values (in3 out3) (make-pipe))

  (define (shutdown-all)
    (write-json "shutdown" out0)
    (write-json "shutdown" out1)
    (write-json "shutdown" out2)
    (write-json "shutdown" out3))

  (define msg1 (hash 'id 0
                     'rest (hash 'id 3
                                 'rest
                                 (hash 'data "msg1"))))

  (define msg2 (hash 'id 1
                     'rest (hash 'id 2
                                 'rest
                                 (hash 'id 1
                                       'rest (hash 'id 3
                                                   'rest
                                                   (hash 'data "msg2"))))))

  (define msg3 (hash 'id 0
                     'rest (hash 'id 2
                                 'rest
                                 (hash 'id 3
                                       'rest (hash 'id 3
                                                   'rest
                                                   (hash 'data "msg3"))))))

  (define msg4 (hash 'id 3
                     'rest
                     (hash 'data "msg4")))

  (define msg5 (hash 'id 1
                     'rest (hash 'id 0
                                 'rest
                                 (hash 'data "msg5"))))

  (define msg6 (hash 'id 3
                     'rest (hash 'id 1
                                 'rest
                                 (hash 'data "msg6"))))

  (thread (thunk (make-and-start-node 0 routing-table in0)))
  (thread (thunk (make-and-start-node 1 routing-table in1)))
  (thread (thunk (make-and-start-node 2 routing-table in2)))
  (thread (thunk (make-and-start-node 3 routing-table in3)))

  (sleep 1)
  (write-json msg1 out1)
  (sleep 1)
  (write-json msg2 out0)
  (sleep 2)
  (write-json msg3 out3)
  (sleep 1)
  (write-json msg4 out2)
  (sleep 1)
  (write-json msg5 out0)
  (sleep 1)
  (write-json msg6 out1)

  (sleep 10)

  (shutdown-all)
  (custodian-shutdown-all (current-custodian)))