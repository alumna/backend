module Alumna
  # Outbound socket on this process. Not Crystal `Socket` (IP/Unix).
  # Tests use a fake. Production wraps HTTP::WebSocket.
  abstract class PushSocket
    abstract def send(payload : String | Bytes) : Nil
    abstract def close : Nil
  end

  # Local connection table. Delivery is this process only. Not a NATS bus.
  abstract class Connections
    abstract def register(id : String, socket : PushSocket) : Nil
    abstract def unregister(id : String) : Nil
    # True if the id is registered and send did not fail.
    abstract def send(id : String, payload : String | Bytes) : Bool
    abstract def watch(id : String, topic : String) : Nil
    abstract def unwatch(id : String, topic : String) : Nil
    abstract def send_topic(topic : String, payload : String | Bytes) : Nil
    abstract def close_all : Nil
  end
end
