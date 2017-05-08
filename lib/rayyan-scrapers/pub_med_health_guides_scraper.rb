module RayyanScrapers
  class PubMedHealthGuidesScraper < PubMedHealthScraper
    def initialize
      super
      @search_url = "#{@base_url}/s/clinical_guides_medrev"
      @logger.debug "PubMedHealthGuides scraper initialized"
    end
  end
end
