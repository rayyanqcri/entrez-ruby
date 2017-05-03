module RayyanScrapers
  class CSXScraper < EntrezScraper
    def initialize(query, logger = nil)
      super(query, logger)

      @base_url = 'http://10.153.18.33:5000/api/v1'
      @search_url = "#{@base_url}/search?db=csx"
      @detail_url = "#{@base_url}/fetch?db=csx&retmode=xml"
      @detail_friendly_url = "http://citeseerx.ist.psu.edu/viewdoc/summary?doi="
      @refs_url = "#{@base_url}/link?dbfrom=csx&db=csx"
      @refs_link_name = "csx_csx_refs"
      @cited_link_name = "csx_csx_citedin"

      @source = Source.find_by_name 'CiteSeerX'
      @xml_idtype = 'csx'
      @db_idtype = 'csx'

      @xml_element_data = 'CSXData'
      @xml_element_citation = 'CSXCitation'
      @xml_element_bookdata = 'CSXBookData'
      @xml_element_root = 'CSXArticleSet'
      @xml_element_root_article = 'CSXArticle'
      @xml_element_root_book = 'CSXBookArticle'
    end

    def self.max_pages_to_scrape
      ENV['CSX_MAX_PAGES'].to_i
    end
    
    def self.results_per_page
      ENV['CSX_RESULTS_PER_PAGE'].to_i
    end
  end
end
