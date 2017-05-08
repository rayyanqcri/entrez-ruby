module RayyanScrapers
  class PubMedHealthDareScraper < PubMedHealthScraper
    def initialize
      super
      @search_url = "#{@base_url}/s/dare_reviews_medrev"
      @logger.debug "PubMedHealthDARE scraper initialized"
    end
  end
end
