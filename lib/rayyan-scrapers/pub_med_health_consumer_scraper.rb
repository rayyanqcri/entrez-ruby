module RayyanScrapers
  class PubMedHealthConsumerScraper < PubMedHealthScraper
    def initialize
      super
      @search_url = "#{@base_url}/s/for_consumers_medrev"
      @logger.debug "PubMedHealthConsumer scraper initialized"
    end
  end
end
