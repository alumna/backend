module Alumna
  class App
    # One fiber. The first action is sleep, then the block, then sleep again.
    # close sets the stop flag. The fiber reads it after sleep and does not start another pass.
    # A block that has started runs until it returns. interval must be greater than zero.
    def every(interval : Time::Span, &block : -> Nil) : Nil
      raise ArgumentError.new("interval must be > 0") unless interval > Time::Span.zero
      spawn do
        loop do
          sleep interval
          break if @stopping.get(:acquire)
          block.call
        end
      end
    end

    # close runs these once, in order, before it closes sockets.
    # Register before listen. A raise skips later hooks and skips the socket close.
    def on_stop(&block : -> Nil) : Nil
      hooks = @stop_hooks
      if hooks.nil?
        hooks = [] of Proc(Nil)
        @stop_hooks = hooks
      end
      hooks << block
    end
  end
end
