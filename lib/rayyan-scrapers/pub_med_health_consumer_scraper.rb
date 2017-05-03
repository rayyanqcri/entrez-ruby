module RayyanScrapers
  class PubMedHealthConsumerScraper < PubMedHealthScraper
    def initialize(query)
      super(query)
      @search_url = "#{@base_url}/s/for_consumers_medrev"
      @logger.debug "PubMedHealthConsumer scraper initialized with query #{@query}"
    end
  end
end
