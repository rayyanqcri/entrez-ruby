require 'nokogiri'
require_relative '../support/hercules'
require_relative '../support/blank'
require_relative '../support/dummy_logger'

module RayyanScrapers
  class ScraperBase
    def initialize(logger = nil, moneta_options = nil)
      @site_id = 'UNKNOWN'
      # During capybara tests (stubbed Typheous, no cache), hydra stops processing queue on reaching @max_parallel_articles!
      #@max_parallel_articles = 20
      @max_parallel_articles = 50
      @max_parallel_refpages = 10

      @logger = logger || DummyLogger.new

      @hercules_articles = Hercules.new @logger, {:max_concurrency => @max_parallel_articles}, moneta_options
      @hercules_refpages = Hercules.new @logger, {:max_concurrency => @max_parallel_refpages}, moneta_options

      @headers = {headers: {"User-Agent"=>"Mozilla/5.0"}}
    end

    def scrape(search_type)
      @logger.info "Scraping as #{self.class.name}"
      t1 = Time.now

      case search_type
      when :topic
        page = get_start_page
        total = total_pages page
        @logger.info "Total results: #{total}"
        iterate_list_pages(page) {|item| yield item, total if block_given?}
      when :ref, :cited
        total = total_pages nil
        iterate_input_items(search_type) {|item| yield item, total if block_given?}
      when :manual
        total = total_pages nil
        iterate_manual_entries {|item| yield item, total if block_given?}
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

    def iterate_list_pages(page, &block)
      page_id = 1
      while page != nil
        @logger.info "Processing page #{page_id}..."
        process_list_page(page, &block)
        page_id += 1
        unless enough_pages page_id
          url = get_next_page_link page, page_id
          page = url ? Typhoeus::Request.get(url, @headers) : nil
        else
          @logger.info "Stopping at this page, enough results!"
          page = nil
        end
      end
    end

    def enough_pages(page_id)
      self.class.max_pages_to_scrape > 0 && page_id > self.class.max_pages_to_scrape
    end

    def self.node_text(page, xpath)
      n = page.at(xpath)
      n = n.text.strip if n
    end

    def self.node_html(page, xpath)
      n = page.at(xpath)
      n = n.inner_html.strip if n
    end

    # functions to override in subclasses

    def self.max_pages_to_scrape; 0 end
    def self.max_results; max_pages_to_scrape * results_per_page end
    def total_pages(page); 'Unknown' end

    def self.results_per_page; raise 'Not implemented' end
    def iterate_input_items(search_type); raise 'Not implemented' end
    def iterate_manual_entries; raise 'Not implemented' end
    def get_start_page; raise 'Not implemented' end
    def get_next_page_link(page, page_id); raise 'Not implemented' end
    def process_list_page(page); raise 'Not implemented' end
    def get_detail; raise 'Not implemented' end
    def process_detail_page; raise 'Not implemented' end
  end
end
