=begin 
  In order to prepare the server for this scraper,
  setup a webserver to host the NIH fulltext folders
  The document root should contain subfolders named below in create_search_url method
  Each subfolder should contain the *.nxml files directly
  For the PMH folder which contains subfolders of books, run these commands first inside the PMH folder:
  1- find -type d -exec basename {} \; | while read l; do if [ $l != . ]; then mv -v $l .$l; fi; done
  2- find -type f -exec ln -s {} \;
  The first command hides the book folders so that they don't appear in the served index page
  The second command creates symlinks to all files in book folders in the PMH folder
=end

module RayyanScrapers
  class NihFulltextScraper < PubMedScraper
    def initialize(query, logger = nil, moneta_options = nil)
      super(query, logger, moneta_options)
      @refs_url = "#{@base_url}/elink.fcgi?dbfrom=pmc&db=pubmed"
      @refs_link_name = "pmc_refs_pubmed"

      @base_url = 'http://localhost:8000/fromNIH'
      @logger.debug "NIH Fulltext scraper initialized"
    end

    def create_search_url(page, page_id)
      section = case page_id
      when 1
        'DARE'
      when 2
        'SYST_REVIEWS_FROM_PUBMED'
      when 3
        'SYST_REVIEWS_FROM_PMH'
      end
      "#{@base_url}/#{section}"
      # "#{@base_url}/samples/PMCsamples"  # TODO REMOVE
    end
    
    def get_start_page
      create_search_url nil, 1
    end

    def self.max_pages_to_scrape
      1 # TODO MAKE 3
    end

    def total_pages(page)
      0
    end
   
    def get_next_page_link(page, page_id)
      create_search_url page, page_id rescue nil
    end

    # NOTUSED by islam
    def process_list_page(page)
      @logger.info("Processing list page with URL: #{page.uri}")
      #page.save_as "html/result-list.html"

      new_items_found = nil

      items = page.links #[0..50]   # TODO REMOVE [], getting sample only
      items_len = items.length - 1
      @total = @total + items_len
  #    pline "Found #{items_len} items in page", true
      items.each do |anchor|
        next if anchor.text == '../'

        new_items_found = false if new_items_found.nil? 
      
        pid = anchor.text.split('.').first
        link = "#{page.uri}#{anchor.href}"
        
        @logger.info "Got result with id #{pid}"
        
  #      pline "  Item #{@curr_property} of #{@total}..."
        # get detailed info

        begin
          article = Article.find_by_url link
          if article.nil?
            new_items_found = true
            article = process_fulltext_detail_page(@agent.get(link), pid)
            yield article, true
          else
            yield article, false
          end
        rescue => exception
          @logger.error "Error processing #{link}:"
          @logger.error exception
          @logger.error exception.backtrace.join("\n")
        end
        @curr_property = @curr_property + 1
      end
      new_items_found
    end

    # NOTUSED (called in a method that is not used) by islam
    def process_fulltext_detail_page(page, pid)
      mArticle = Article.new
      mArticle.source = @source
      mArticle.sid = pid
      mArticle.url = page.uri.to_s

      xml = Nokogiri::XML.parse(page.body, page.request.url.to_s)
      if pid.start_with? "PMC"
        process_fulltext_article_detail_page(xml, mArticle)
      elsif pid.start_with? "PMH"
        process_fulltext_book_detail_page(xml, mArticle)
      else
        @logger.warn "Unknown XML format for PID #{pid} with url #{mArticle.url}"
      end
      
      mArticle.save
      mArticle
    end

    # NOTUSED (called in a method that is not used) by islam
    # also this method calls many other methods that are not used elsewhere
    def process_fulltext_article_detail_page(xml, mArticle)
      article = xml.at '/article'
      article_type = article['article-type']
      mArticle.publication_types << PublicationType.where(name: article_type).first_or_create

      NihFulltextScraper.extract_journal article/'./front/journal-meta', mArticle

      article_meta = article/'./front/article-meta'
      NihFulltextScraper.extract_idtypes article_meta, mArticle, './article-id[@pub-id-type!="pmc"]'
      mArticle.title = ScraperBase.node_text article_meta, './title-group/article-title'
      NihFulltextScraper.extract_authors article_meta, mArticle
      mArticle.jcreated_at = NihFulltextScraper.extract_date article_meta, './pub-date'
      mArticle.jvolume = ScraperBase.node_text article_meta, './volume'
      mArticle.jissue = ScraperBase.node_text article_meta, './issue'
      mArticle.pagination = NihFulltextScraper.extract_pagination article_meta
      mArticle.copyright = ScraperBase.node_text article_meta, './/copyright-statement'
      NihFulltextScraper.extract_abstracts article_meta, mArticle
      NihFulltextScraper.extract_sections article, mArticle, './body/sec', 'body'
      # TODO: TEST REFS COUNT
      NihFulltextScraper.extract_refs article, mArticle
    end

    # NOTUSED (called in a method that is not used) by islam
    def process_fulltext_book_detail_page(xml, mArticle)
      article = xml.at '/book-part'
      mArticle.language = article['xml:lang']

      article_meta = article/'./book-meta'
      NihFulltextScraper.extract_idtypes article_meta, mArticle, './book-id'

      chapter_id, chapter_title = NihFulltextScraper.extract_chapter_title article, mArticle

      NihFulltextScraper.extract_authors article_meta, mArticle
      mArticle.article_date = NihFulltextScraper.extract_date article_meta, './pub-date'
      mArticle.jvolume = ScraperBase.node_text article_meta, './volume'
      series = ScraperBase.node_text article_meta, './series'
      mArticle.publication_types << PublicationType.where(name: series).first_or_create unless series.nil?
      NihFulltextScraper.extract_collection article_meta, mArticle
      mArticle.copyright = ScraperBase.node_text article_meta, './/copyright-statement'
      NihFulltextScraper.extract_abstracts article_meta, mArticle
      NihFulltextScraper.extract_sections article, mArticle, './body', chapter_id, chapter_title

    end

    # NOTUSED by islam
    def self.extract_journal(xml, mArticle)
      abbr = ScraperBase.node_text xml, './journal-id'
      title = ScraperBase.node_text xml, './journal-title'
      issn = ScraperBase.node_text xml, './issn'
      
      mJournal = Journal.find_by_issn issn
      if mJournal.nil?
        mArticle.build_journal :issn => issn, 
                                :title => title,
                                :abbreviation => abbr
      else
        mArticle.journal = mJournal
      end
      
      publisher = ScraperBase.node_text xml, './publisher/publisher-name'
      loc = ScraperBase.node_text xml, './publisher/publisher-loc'
      mPublisher = Publisher.find_by_name publisher
      if mPublisher.nil?
        mArticle.build_publisher name: publisher, location: loc
      else
        mArticle.publisher = mPublisher
      end
    end

    def self.extract_idtypes(xml, mArticle, xpath)
      (xml/xpath).map do |id|
        idtype = id['pub-id-type']
        value = id.text
        mArticle.article_ids.build :idtype => idtype, :value => value
        value
      end
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_authors(xml, mArticle)
      affiliations = []
      (xml/'./contrib-group/contrib[@contrib-type="author"]').each do |author|
        lastname = ScraperBase.node_text author, './name/surname'
        firstname = ScraperBase.node_text author, './name/given-names'

        affiliation_name = author.at './aff/text()'
        if affiliation_name.nil?
          affiliation_id = author.at './xref[@ref-type="aff"]/@rid'
          affiliation_name = xml.at "./aff[@id='#{affiliation_id}']/text()"
        end
        unless affiliation_name.nil?
          affiliations << affiliation_name
        end

        mAuthor = (Author.where :firstname => firstname, :lastname => lastname).first
        if mAuthor.nil?
          mAuthor = mArticle.authors.build :firstname => firstname, 
                                  :lastname => lastname
        else
          mArticle.authors << mAuthor
        end
      end
      article_affiliation = xml.at './contrib-group/aff/text()'
      unless article_affiliation.nil?
        affiliations << article_affiliation
      end
      mArticle.affiliation = affiliations.uniq.join(" --\n") unless affiliations.empty?
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_date(xml, xpath)
      year = xml.at("#{xpath}/year/text()")
      month = xml.at("#{xpath}/month/text()")
      day = xml.at("#{xpath}/day/text()")
      ScraperBase.to_date year, month, day
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_abstracts(xml, mArticle)
      (xml/'./abstract/p').each do |abstract|
        mArticle.abstracts.build  :label => ScraperBase.node_text(abstract, './bold'),
                                  :content => ScraperBase.node_text(abstract, './text()')
      end
      (xml/'./abstract/sec').each do |abstract|
        mArticle.abstracts.build  :label => ScraperBase.node_text(abstract, './title'),
                                  :content => (abstract/'./p').map{|p|p.text}.join("\n")
      end
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_sections(xml, mArticle, xpath, parent_location, parent_title = '')
      counter = 1
      (xml/xpath).each do |section|
        title = ScraperBase.node_text section, './title' || parent_title
        location = "#{parent_location}.#{counter.to_s.rjust(5, "0")}"
        code = section['sec-type'] || location
        label = ScraperBase.node_text section, './label'

        mSection = mArticle.sections.build  code: code,
                                            location: location,
                                            title: title,
                                            label: label

        (section/'./p').each do |para|
          mSection.paragraphs.build html: para.inner_html
        end

        NihFulltextScraper.extract_sections section, mArticle, './sec', location, title
        counter = counter + 1
      end
    end

    def self.update_section_titles(xml, mArticle, xpath, parent_location)
      counter = 1
      (xml/xpath).each do |section|
        title = ScraperBase.node_text section, './title' || 'Section'
        location = "#{parent_location}.#{counter.to_s.rjust(5, "0")}"

        mSection = mArticle.sections.find_by_location location
        mSection.title = title
        raise "Could not save section with id #{mSection.id}" unless mSection.save

        NihFulltextScraper.update_section_titles section, mArticle, './sec', location
        counter = counter + 1
      end
    end

    def self.update_sections_more_details(xml, mArticle, xpath, parent_location)
      counter = 1
      (xml/xpath).each do |section|
        location = "#{parent_location}.#{counter.to_s.rjust(5, "0")}"
        mSection = mArticle.sections.find_by_location location
        mSection.indexed = section['indexed'] != "false"
        children = section/('./node()[not(self::title) and not(self::label) and not(self::sec-meta) and not(self::comment())]')
        mSection.has_reflist_only = children && children.length == 1 && children.first.node_name == 'ref-list'

        sectypes = mSection.section_types.map(&:id)
        parsed_sectypes = section['sec-type']
        unless parsed_sectypes.blank?
          parsed_sectypes.downcase.strip.split(/\s*[,\|_\.\/]\s*|\s*and\s*/).each do |sectype|
            if sectype.start_with? 'ch'
              sectype = 'chapter'
            elsif sectype.start_with? 'sec'
              sectype = 'section'
            elsif sectype.start_with? 'subsec'
              sectype = 'subsection'
            elsif sectype.start_with? 'subsubsec'
              sectype = 'subsubsection'
            end
            if sectype.match(/^A[0-9]+$/).nil?
              mSectype = SectionType.find_by_name(sectype)
              if mSectype.nil?
                #puts "NEW sectype found: #{sectype}"
                mSection.section_types.create :name => sectype
              elsif not sectypes.include? mSectype.id
                #puts "Old sectype found: #{sectype} having id #{mSectype.id}"
                mSection.section_types << mSectype
              end
            end
          end
        end

        raise "Could not save section with id #{mSection.id}" unless mSection.save

        NihFulltextScraper.update_sections_more_details section, mArticle, './sec', location
        counter = counter + 1
      end
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_pagination(xml)
      fpage = ScraperBase.node_text(xml, './fpage')
      lpage = ScraperBase.node_text(xml, './lpage')
      lpage = lpage || ScraperBase.node_text(xml, './page-range')
      "#{fpage}-#{lpage}"
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_chapter_title(xml, mArticle)
      book_title = ScraperBase.node_text xml, './book-meta/book-title-group/book-title'
      chapter_title = (ScraperBase.node_text xml, './book-part-meta/title-group/subtitle') ||
        (ScraperBase.node_text xml, './book-part-meta/title-group/title') ||
        'Chapter'
      chapter_id = (ScraperBase.node_text xml, './book-part-meta/elocation-id') ||
        'chapter'

      mArticle.title = "#{book_title} [#{chapter_title}]"
      return chapter_id, chapter_title
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_collection(xml, mArticle)
      collection = xml.at './/related-object[@link-type="collection-link" and @content-type="collection"]'
      code = collection['source-id']
      title = collection.text
      mCollection = Collection.find_by_code code
      if mCollection.nil?
        mArticle.build_collection :code => code, :title => title
      else
        mArticle.collection = mCollection
      end
    end

    # NOTUSED (called in a method that is not used) by islam
    def self.extract_refs xml, mArticle
      mArticle.refs_count = xml.at('count(./back/ref-list/ref)')
    end
  end
end
