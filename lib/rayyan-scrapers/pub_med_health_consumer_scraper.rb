module RayyanScrapers
  class PubMedHealthConsumerScraper < PubMedHealthScraper
    def initialize(query, content_dir = 'pubmedhealthconsumer-contents')
      super(query, content_dir)
      @search_url = "#{@base_url}/s/for_consumers_medrev"
      @logger.debug "PubMedHealthConsumer scraper initialized with query #{@query}"
      @source = Source.find_by_name 'PubMed Health Consumer'
    end
  end
end
