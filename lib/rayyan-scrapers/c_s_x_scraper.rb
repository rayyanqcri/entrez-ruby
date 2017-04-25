module RayyanScrapers
  class CSXScraper < EntrezScraper
    def initialize(query, content_dir = 'csx-contents', log_file = 'csx.log')
      super(query, content_dir, log_file)

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

    def process_article_detail_page(xml, mArticle, extraction_fields)
      article_xml = xml/"./#{@xml_element_citation}/Article"
      super(xml, article_xml, mArticle, extraction_fields)
      #CSXScraper.extract_venue_info article_xml, mArticle if extraction_fields[:journal]
    end

    def self.extract_venue_info(xml, mArticle)
      venue = xml/'./Venue'
      venueType = (venue/'./VenueType').text.try(:upcase)
      title = (venue/'./Title').text

      mArticle.venue = Venue.where(venueType: venueType, title: title).first_or_initialize

      if venueType == 'JOURNAL'
        mArticle.journal = Journal.where(title: title).first_or_initialize
        mArticle.jvolume = (venue/'./Volume').text
        mArticle.jissue = (venue/'./Issue').text
        mArticle.pagination = (venue/'./Pages').text    
        mArticle.jcreated_at = EntrezScraper.extract_date(venue, './PubDate')
      end

    end

  end
end
