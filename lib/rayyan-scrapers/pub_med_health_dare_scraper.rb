module RayyanScrapers
  class PubMedHealthDareScraper < PubMedHealthScraper
    def initialize(query)
      super(query)
      @search_url = "#{@base_url}/s/dare_reviews_medrev"
      @logger.debug "PubMedHealthDARE scraper initialized with query #{@query}"
    end
  end
end
