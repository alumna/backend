require "mutex"

module Alumna
  # In-process sockets. One instance per App. Mutex for preview_mt.
  class MemoryConnections < Connections
    def initialize
      @mutex = Sync::Mutex.new
      @sockets = {} of String => PushSocket
      @ids_by_topic = {} of String => Set(String)
      @topics_by_id = {} of String => Set(String)
    end

    def register(id : String, socket : PushSocket) : Nil
      raise ArgumentError.new("connection id must not be empty") if id.empty?
      @mutex.synchronize { @sockets[id] = socket }
    end

    def unregister(id : String) : Nil
      @mutex.synchronize do
        @sockets.delete(id)
        if topics = @topics_by_id.delete(id)
          topics.each do |topic|
            if ids = @ids_by_topic[topic]?
              ids.delete(id)
              @ids_by_topic.delete(topic) if ids.empty?
            end
          end
        end
      end
    end

    def send(id : String, payload : String | Bytes) : Bool
      socket = @mutex.synchronize { @sockets[id]? }
      return false unless socket
      socket.send(payload)
      true
    rescue IO::Error
      false
    end

    def watch(id : String, topic : String) : Nil
      raise ArgumentError.new("connection id must not be empty") if id.empty?
      raise ArgumentError.new("topic must not be empty") if topic.empty?
      @mutex.synchronize do
        ids = @ids_by_topic[topic] ||= Set(String).new
        ids << id
        topics = @topics_by_id[id] ||= Set(String).new
        topics << topic
      end
    end

    def unwatch(id : String, topic : String) : Nil
      @mutex.synchronize do
        if ids = @ids_by_topic[topic]?
          ids.delete(id)
          @ids_by_topic.delete(topic) if ids.empty?
        end
        if topics = @topics_by_id[id]?
          topics.delete(topic)
          @topics_by_id.delete(id) if topics.empty?
        end
      end
    end

    # Snapshot watchers, then send outside the mutex so send IO cannot deadlock.
    def send_topic(topic : String, payload : String | Bytes) : Nil
      sockets = [] of PushSocket
      @mutex.synchronize do
        ids = @ids_by_topic[topic]?
        if ids
          ids.each do |id|
            if socket = @sockets[id]?
              sockets << socket
            end
          end
        end
      end
      sockets.each do |socket|
        begin
          socket.send(payload)
        rescue IO::Error
        end
      end
    end

    def close_all : Nil
      sockets = [] of PushSocket
      @mutex.synchronize do
        @sockets.each_value { |socket| sockets << socket }
        @sockets.clear
        @ids_by_topic.clear
        @topics_by_id.clear
      end
      sockets.each do |socket|
        begin
          socket.close
        rescue IO::Error
        end
      end
    end
  end
end
