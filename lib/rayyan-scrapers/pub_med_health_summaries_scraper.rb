module RayyanScrapers
  class PubMedHealthSummariesScraper < PubMedHealthScraper
    def initialize
      super
      @search_url = "#{@base_url}/s/executive_summaries_medrev"
      @logger.debug "PubMedHealthSummaries scraper initialized"
    end
  end
end
