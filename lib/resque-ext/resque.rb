module Resque

  def self.enqueued?( klass, *args)
    enqueued_in?(queue_from_class(klass), klass, *args )
  end

  def self.enqueued_in?(queue, klass, *args)
    item = { :class => klass.to_s, :args => args }
    return nil unless Resque::Plugins::Loner::Helpers.item_is_a_unique_job?(item)
    Resque::Plugins::Loner::Helpers.loner_queued?(queue, item)
  end

  def self.remove_queue_with_loner_cleanup(queue)
    self.remove_queue_without_loner_cleanup(queue)
    Resque::Plugins::Loner::Helpers.cleanup_loners(queue)
  end


  class << self

    alias_method :remove_queue_without_loner_cleanup, :remove_queue
    alias_method :remove_queue, :remove_queue_with_loner_cleanup

    if defined? Resque::Helpers
      # Silence our dear warnings…
      begin
        old_verbose, $VERBOSE = $VERBOSE, nil
        helpers = Object.new.extend(Resque::Helpers)
      ensure
        $VERBOSE = old_verbose
      end

      # Provide fallbacks if our Resque doesn't provide
      # Resque.encode/Resque.decode yet.
      Resque.respond_to?(:encode) or
        define_method(:encode) do |*a|
          helpers.encode(*a)
        end

      Resque.respond_to?(:decode) or
        define_method(:decode) do |*a|
          helpers.decode(*a)
        end
    end
  end
end
