require 'nokogiri'
require_relative '../support/hercules'
require_relative '../support/blank'
require_relative '../support/dummy_logger'

module RayyanScrapers
  class ScraperBase

    DEFAULT_MAX_PARALLEL_ARTICLES = 50
    DEFAULT_MAX_PARALLEL_REFPAGES = 10

    def initialize(logger = nil, moneta_options = nil)
      @site_id = 'UNKNOWN'
      # During capybara tests (stubbed Typheous, no cache), hydra stops processing queue on reaching @max_parallel_articles!
      @max_parallel_articles = self.class.max_parallel_articles
      @max_parallel_refpages = self.class.max_parallel_refpages

      @logger = logger || DummyLogger.new

      @hercules_articles = Hercules.new @logger, {:max_concurrency => @max_parallel_articles}, moneta_options
      @hercules_refpages = Hercules.new @logger, {:max_concurrency => @max_parallel_refpages}, moneta_options

      @headers = {headers: {"User-Agent"=>"Mozilla/5.0"}}
    end

    def scrape
      @logger.info "Scraping as #{self.class.name}"
      t1 = Time.now

      page = get_start_page
      total = total_pages page
      @logger.info "Total results: #{total}"
      iterate_list_pages(page) {|item| yield item, total if block_given?}

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
        items_count = process_list_page(page, &block)
        page_id += 1
        if items_count == 0 || enough_pages(page_id)
          @logger.info "Stopping at this page"
          page = nil
        else
          url = get_next_page_link page, page_id
          page = url ? Typhoeus::Request.get(url, @headers) : nil
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

    def self.max_parallel_articles
      (ENV['SCRAPERS_MAX_PARALLEL_ARTICLES'] || DEFAULT_MAX_PARALLEL_ARTICLES).to_i
    end

    def self.max_parallel_refpages
      (ENV['SCRAPERS_MAX_PARALLEL_REFPAGES'] || DEFAULT_MAX_PARALLEL_REFPAGES).to_i
    end

    # functions to override in subclasses

    def self.max_pages_to_scrape; 0 end
    def self.max_results; max_pages_to_scrape * results_per_page end
    def total_pages(page); 'Unknown' end

    def self.results_per_page; raise 'Not implemented' end
    def get_start_page; raise 'Not implemented' end
    def get_next_page_link(page, page_id); raise 'Not implemented' end
    def process_list_page(page); raise 'Not implemented' end
    def get_detail; raise 'Not implemented' end
    def process_detail_page; raise 'Not implemented' end
  end
end
