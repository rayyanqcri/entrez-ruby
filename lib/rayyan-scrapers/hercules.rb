module RayyanScrapers
  class Hercules
    attr_accessor :enable_cache

    def initialize(logger, options = {})
      @hydra = Typhoeus::Hydra.new options
      @killed = false
      @pending_requests = 0
      @done_requests = 0
      @max_hydra_queue_length = 200
      @logger = logger
      @after_kill = nil
    end

    # hydra_run
    def fight(heads)
      heads.each do |item|
        yield item
      end
      @hydra.run
    end

    # hydra_queue
    def strike(link, cached_path = nil, yield_exception = false)
      request = Typhoeus::Request.new(link, :followlocation => true, headers: {"User-Agent"=>"Mozilla/5.0"})
      if cached_path && self.enable_cache
        # look for cached version
        if File.exist? cached_path
          log "Cache hit: #{cached_path}", "debug"
          # load from file
          yield request, File.read(cached_path)
          return
        end
      end
      request.on_complete do |response|
        if response.code == 0
          # Could not get an http response, something's wrong.
          err = "ERROR: Unknown error (#{response}) while requesting #{link}"
          log err, "error"
          yield request, Exception.new(err) if yield_exception
        elsif response.timed_out?
          # aw hell no
          err = "ERROR: Timed out while requesting #{link}"
          log err, "error"
          yield request, Exception.new(err) if yield_exception
        elsif response.success? || response.code - 200 < 100
          # in the middle of such dead slow network/processing, I am optimizing a compare and an AND! #funny 
          begin
            ScraperBase.saveResultsToFile cached_path, response.body if cached_path
            yield request, response.body
          rescue => e
            log "WARNING: Exception while processing response for #{link}", "warn"
            log e, "warn"
          end
        else
          # Received a non-successful http response.
          err = "ERROR: HTTP request failed: #{response.code.to_s} while requesting #{link}"
          log err, "error"
          yield request, Exception.new(err) if yield_exception
        end
        @done_requests += 1
        @pending_requests -= 1
        check_killed
      end
      @pending_requests += 1
      @hydra.queue(request)
      log "++++ Hydra has #{@hydra.queued_requests.length} queued requests", "debug"
      # prevent queue from growing too big, thus delaying hydra.run too much
      @hydra.run if @hydra.queued_requests.length > @max_hydra_queue_length
    end

    def kill(&after_kill)
      @killed = true
      @after_kill = after_kill
      check_killed
    end

    def check_killed
      log "+-+-+- pending_requests: #{@pending_requests}, done_requests: #{@done_requests}", "debug"
      return if !@killed || @pending_requests > 0
      @after_kill.call @done_requests if @after_kill
    end

    def log(message, level = "log")
      @logger.send(level, message) if @logger
    end

  end
end
