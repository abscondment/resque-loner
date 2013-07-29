module Resque
  module Plugins
    module Loner
      class Helpers
        # Direct access to the Redis instance.
        def self.redis
          Resque.redis
        end

        def self.loner_queued?(queue, item)
          return false unless item_is_a_unique_job?(item)
          redis.get(unique_job_queue_key(queue, item)) == "1"
        end

        def self.mark_loner_as_queued(queue, item)
          return unless item_is_a_unique_job?(item)
          key = unique_job_queue_key(queue, item)
          redis.set(key, 1)
          unless(ttl=item_ttl(item)) == -1 # no need to incur overhead for default value
            redis.expire(key, ttl)
          end
        end

        def self.mark_loner_as_unqueued(queue, job)
          item = job.is_a?(Resque::Job) ? job.payload : job
          return unless item_is_a_unique_job?(item)
          unless (ttl=loner_lock_after_execution_period(item)) == 0
            redis.expire(unique_job_queue_key(queue, item), ttl)
          else
            redis.del(unique_job_queue_key(queue, item))
          end
        end

        def self.unique_job_queue_key(queue, item)
          job_key = constantize(item[:class] || item["class"]).redis_key(item)
          "loners:queue:#{queue}:job:#{job_key}"
        end

        def self.item_is_a_unique_job?(item)
          begin
            klass = constantize(item[:class] || item["class"])
            klass.included_modules.include?(::Resque::Plugins::UniqueJob)
          rescue
            false # Resque testsuite also submits strings as job classes while Resque.enqueue'ing,
          end     # so resque-loner should not start throwing up when that happens.
        end

        def self.item_ttl(item)
          begin
            constantize(item[:class] || item["class"]).loner_ttl
          rescue
            -1
          end
        end

        def self.loner_lock_after_execution_period(item)
          begin
            constantize(item[:class] || item["class"]).loner_lock_after_execution_period
          rescue
            0
          end
        end

        def self.job_destroy(queue, klass, *args)
          klass = klass.to_s
          redis_queue = "queue:#{queue}"

          redis.lrange(redis_queue, 0, -1).each do |string|
            json   = Resque.decode(string)

            match  = json['class'] == klass
            match &= json['args'] == args unless args.empty?

            if match
             Resque::Plugins::Loner::Helpers.mark_loner_as_unqueued( queue, json )
            end
          end
        end

        def self.cleanup_loners(queue)
          keys = redis.keys("loners:queue:#{queue}:job:*")
          redis.del(*keys) unless keys.empty?
        end

        # Given a word with dashes, returns a camel cased version of it.
        #
        # classify('job-name') # => 'JobName'
        def self.classify(dashed_word)
          dashed_word.split('-').each { |part| part[0] = part[0].chr.upcase }.join
        end

        # Tries to find a constant with the name specified in the argument string:
        #
        # constantize("Module") # => Module
        # constantize("Test::Unit") # => Test::Unit
        #
        # The name is assumed to be the one of a top-level constant, no matter
        # whether it starts with "::" or not. No lexical context is taken into
        # account:
        #
        # C = 'outside'
        # module M
        #   C = 'inside'
        #   C # => 'inside'
        #   constantize("C") # => 'outside', same as ::C
        # end
        #
        # NameError is raised when the constant is unknown.
        def self.constantize(camel_cased_word)
          camel_cased_word = camel_cased_word.to_s

          if camel_cased_word.include?('-')
            camel_cased_word = classify(camel_cased_word)
          end

          names = camel_cased_word.split('::')
          names.shift if names.empty? || names.first.empty?

          constant = Object
          names.each do |name|
            args = Module.method(:const_get).arity != 1 ? [false] : []

            if constant.const_defined?(name, *args)
              constant = constant.const_get(name)
            else
              constant = constant.const_missing(name)
            end
          end
          constant
        end

      end
    end
  end
end
