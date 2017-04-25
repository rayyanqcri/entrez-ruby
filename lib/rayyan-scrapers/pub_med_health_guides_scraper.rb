module RayyanScrapers
  class PubMedHealthGuidesScraper < PubMedHealthScraper
    def initialize(query, content_dir = 'pubmedhealthguides-contents')
      super(query, content_dir)
      @search_url = "#{@base_url}/s/clinical_guides_medrev"
      @logger.debug "PubMedHealthGuides scraper initialized with query #{@query}"
      @source = Source.find_by_name 'PubMed Health Clinical Guides'
    end
  end
end
