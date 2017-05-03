module RayyanScrapers
  class PubMedHealthGuidesScraper < PubMedHealthScraper
    def initialize(query)
      super(query)
      @search_url = "#{@base_url}/s/clinical_guides_medrev"
      @logger.debug "PubMedHealthGuides scraper initialized with query #{@query}"
    end
  end
end
