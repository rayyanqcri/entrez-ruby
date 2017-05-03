require 'typhoeus'

module RayyanScrapers
  class Hercules
    attr_accessor :enable_cache

    def initialize(logger, options = {})
      @hydra = Typhoeus::Hydra.new options
      @killed = false
      @pending_requests = 0
      @done_requests = 0
      @max_hydra_queue_length = 200
      @logger = logger || DummyLogger.new
      @after_kill = nil
      @cache = nil # TODO get from params
    end

    # hydra_run
    def fight(heads)
      heads.each do |item|
        yield item
      end
      @hydra.run
    end

    # hydra_queue
    def strike(link, cache_key = nil, yield_exception = false)
      request = Typhoeus::Request.new(link, :followlocation => true, headers: {"User-Agent"=>"Mozilla/5.0"})
      if @cache && cache_key && self.enable_cache
        # look for cached version
        response = @cache.get(cache_key)
        unless response.nil?
          @logger.debug "Cache hit: #{cache_key}"
          # load from cache
          yield request, response
          return
        end
      end
      request.on_complete do |response|
        if response.code == 0
          # Could not get an http response, something's wrong.
          err = "ERROR: Unknown error (#{response}) while requesting #{link}"
          @logger.error err
          yield request, Exception.new(err) if yield_exception
        elsif response.timed_out?
          # aw hell no
          err = "ERROR: Timed out while requesting #{link}"
          @logger.error err
          yield request, Exception.new(err) if yield_exception
        elsif response.success? || response.code - 200 < 100
          # in the middle of such dead slow network/processing, I am optimizing a compare and an AND! #funny 
          begin
            @cache.set(cache_key, response.body) if @cache && cache_key && self.enable_cache
            yield request, response.body
          rescue => e
            @logger.warn "WARNING: Exception while processing response for #{link}"
            @logger.warn e
          end
        else
          # Received a non-successful http response.
          err = "ERROR: HTTP request failed: #{response.code.to_s} while requesting #{link}"
          @logger.error err
          yield request, Exception.new(err) if yield_exception
        end
        @done_requests += 1
        @pending_requests -= 1
        check_killed
      end
      @pending_requests += 1
      @hydra.queue(request)
      @logger.debug "++++ Hydra has #{@hydra.queued_requests.length} queued requests"
      # prevent queue from growing too big, thus delaying hydra.run too much
      @hydra.run if @hydra.queued_requests.length > @max_hydra_queue_length
    end

    def kill(&after_kill)
      @killed = true
      @after_kill = after_kill
      check_killed
    end

    def check_killed
      @logger.debug "+-+-+- pending_requests: #{@pending_requests}, done_requests: #{@done_requests}"
      return if !@killed || @pending_requests > 0
      @after_kill.call @done_requests if @after_kill
    end
  end
end
