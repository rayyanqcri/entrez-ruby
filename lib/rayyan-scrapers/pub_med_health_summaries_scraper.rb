module RayyanScrapers
  class PubMedHealthSummariesScraper < PubMedHealthScraper
    def initialize(query)
      super(query)
      @search_url = "#{@base_url}/s/executive_summaries_medrev"
      @logger.debug "PubMedHealthSummaries scraper initialized with query #{@query}"
    end
  end
end
