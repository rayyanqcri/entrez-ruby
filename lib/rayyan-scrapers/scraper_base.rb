module RayyanScrapers
  class ScraperBase
    def initialize(log_file = 'scraper.log', content_dir = 'contents')
      @site_id = 'UNKNOWN'
      # During capybara tests (stubbed Typheous, no cache), hydra stops processing queue on reaching @max_parallel_articles!
      #@max_parallel_articles = 20
      @max_parallel_articles = 50
      @max_parallel_refpages = 10

      # use Rails logger (heroku has no files) and filter later
      @logger = Rails.logger

      @hercules_articles = Hercules.new @logger, :max_concurrency => @max_parallel_articles
      @hercules_refpages = Hercules.new @logger, :max_concurrency => @max_parallel_refpages

      @stop_on_seen_page = true
      @content_dir = Rails.root.join(ENV['WRITABLE_DIR']).join(content_dir)
      FileUtils.mkdir_p(@content_dir) unless File.directory?(@content_dir)

      @headers = {headers: {"User-Agent"=>"Mozilla/5.0"}}
    end

    def self.saveResultsToFile(fileName, results)
      begin
        f = File.new(fileName, 'w')
        results.force_encoding("utf-8") # HACK! SHOULD GET CORRECT ENCODING
        f.write(results)
      rescue => e
        Rails.logger.error e
      ensure
        f.close if f
      end
    end

    # helsayed NOTUSED
    def ScraperBase.read_file(fileName)
      f = File.new(fileName, 'r')
      c = f.read()
      f.close()
      c.each_line do |l|
        yield l.chomp!
      end
    end

    def scrape(search_type, enable_cache = true)
      @hercules_articles.enable_cache = @hercules_refpages.enable_cache = enable_cache
      @logger.info "Scraping as #{self.class.name} with caching #{enable_cache ? 'enabled' : 'disabled'}"
      t1 = Time.now

      case search_type
      when :topic
        page = get_start_page
        iterate_list_pages(page) {|item, isnew| yield item, isnew, @total if block_given?}
      when :ref, :cited
        iterate_input_items(search_type) {|item, isnew| yield item, isnew, @total if block_given?}
      when :manual
        iterate_manual_entries {|item, isnew| yield item, isnew, @total if block_given?}
      end

      @hercules_refpages.kill do |done_requests_refpages|
        @hercules_articles.kill do |done_requests_articles|
          @logger.info "hercules_articles killed hydra"
          tdiff = Time.now - t1
          done_requests = done_requests_refpages + done_requests_articles
          @logger.info "FINISHED #{done_requests} requests in #{tdiff.round} seconds (#{done_requests/tdiff} r/s)"
        end
      end
    end

    def iterate_list_pages(page)
      @total = total_pages page
      @logger.info "Total results: #{@total}"
      @curr_property = 1
      @curr_page = 1
      while page != nil
        @logger.info "Processing page #{@curr_page}..."
        new_items_found = process_list_page(page) do |item, isnew|
          yield item, isnew
        end
        if new_items_found or (new_items_found == false and not @stop_on_seen_page)
          #page.save_as("list#{@curr_page}.html")
          @curr_page = @curr_page + 1
          if self.class.max_pages_to_scrape == 0 or @curr_page <= self.class.max_pages_to_scrape
            url = get_next_page_link(page)
            if url
              #page = @agent.get(url)
              page = Typhoeus::Request.get(url, @headers)
            else
              page = nil
            end
          else
            @logger.info "\nStopping at this page, enough results!"
            page = nil
          end
        else
          @logger.info "\nNo new items found on this page, stopping!"
          page = nil
        end
      end
    end

    def self.node_text(page, xpath)
      n = page.at(xpath)
      n = n.text.strip if n
    end

    def self.node_html(page, xpath)
      n = page.at(xpath)
      n = n.inner_html.strip if n
    end

    def self.to_date(year, month = 1, day = 1)
      day_i, month_i = day.to_s.to_i, month.to_s.to_i
      day = 1 if day.blank? || day_i <= 0 || day_i > 31
      month = 1 if month.blank? || month_i <= 0 || month_i > 12
      day.strip! if day.instance_of? String
      month.strip! if month.instance_of? String
      year.strip! if year.instance_of? String
      return nil if year.blank? or year.to_s.to_i <= 0
      date = begin
        "#{year}-#{month}-#{day}".gsub(/\s/, '').to_date
      rescue
        begin
          "#{year}-#{month}-1".gsub(/\s/, '').to_date
        rescue
          begin
            "#{year}-1-1".gsub(/\s/, '').to_date
          rescue
            nil
          end
        end
      end
    end

    # functions to override in subclasses

    def get_start_page
      raise 'Not implemented'
    end

    def self.max_pages_to_scrape
      0
    end

    def self.results_per_page
      raise 'Not implemented'
    end

    def self.max_results
      max_pages_to_scrape * results_per_page
    end

    def total_pages(page)
      'Unknown'
    end

    def get_next_page_link page
      raise 'Not implemented'
    end

    def process_list_page page
      raise 'Not implemented'
    end

    def get_detail
      raise 'Not implemented'
    end

    def process_detail_page
      raise 'Not implemented'
    end
  end
end
