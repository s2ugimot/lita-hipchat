require "lita"
require "lita/adapters/hipchat/connector"

module Lita
  module Adapters
    class HipChat < Adapter
      namespace "hipchat"

      # Required attributes
      config :jid, type: String, required: true
      config :password, type: String, required: true

      # Optional attributes
      config :server, type: String, default: "chat.hipchat.com"
      config :debug, type: [TrueClass, FalseClass], default: false
      config :rooms, type: [Symbol, Array]
      config :muc_domain, type: String, default: "conf.hipchat.com"
      config :ignore_unknown_users, type: [TrueClass, FalseClass], default: false
      config :reconnection_delay, type: Fixnum, default: 0

      attr_reader :connector

      def initialize(robot)
        super
        @reconnection_lock = Mutex.new
        initialize_connector
      end

      def join(room_id)
        connector.join(muc_domain, room_id)
        robot.trigger(:joined, room: room_id)
      end

      def mention_format(name)
        "@#{name}"
      end

      def part(room_id)
        robot.trigger(:parted, room: room_id)
        connector.part(muc_domain, room_id)
      end

      def run
        connect_and_join
        sleep
      rescue Interrupt
        shut_down
      end

      def reconnect
        thread_id = Thread.current.object_id.to_s(36)
        if @reconnection_lock.try_lock
          begin
            log.info "Thread: #{thread_id}: Reconnection started."
            initialize_connector
            connect_and_join
            log.info "Thread: #{thread_id}: Reconnection completed successfully."
            robot.trigger(:reconnected)
          ensure
            @reconnection_lock.unlock
          end
        else
          log.info "Thread: #{thread_id}: Other thread is processing reconnection. Closing this thread."
        end
      end

      def send_messages(target, strings)
        if target.private_message?
          connector.message_jid(target.user.id, strings)
        else
          connector.message_muc(target.room, strings)
        end
      end

      def set_topic(target, topic)
        connector.set_topic(target.room, topic)
      end

      def shut_down
        rooms.each { |r| part(r) }
        connector.shut_down
        robot.trigger(:disconnected)
      end

      private

      def initialize_connector
        @connector = Connector.new(robot, config.jid, config.password, config.server, debug: config.debug)
        if config.reconnection_delay > 0
          log.info "Registering reconnection handler"
          connector.register_reconnection_handler(method(:reconnect), config.reconnection_delay)
        end
      end

      def connect_and_join
        connector.connect
        robot.trigger(:connected)
        rooms.each { |r| join(r) }
      end

      def rooms
        if config.rooms == :all
          connector.list_rooms(muc_domain)
        else
          Array(config.rooms)
        end
      end

      def muc_domain
        config.muc_domain.dup
      end

    end

    Lita.register_adapter(:hipchat, HipChat)
  end
end
