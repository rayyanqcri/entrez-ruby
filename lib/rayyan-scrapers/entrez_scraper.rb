module RayyanScrapers
  class EntrezScraper < ScraperBase
    attr_reader :query

    DEFAULT_EXTRACTION_FIELDS = {
      title: 1,
      copyright: 1,
      affiliation: 1,
      language: 1,
      dates: 1,
      pubtypes: 1,
      journal: 1,
      abstracts: 1,
      authors: 1,
      idtypes: 1,
      keyphrases: 1,
      publisher: 1,
      collection: 1,
      sections: 1
    }

    def initialize(query, logger = nil)
      super(logger)

      begin
        @query = query.map do |topic_query|
          "(" + topic_query.map do |keyword|
            URI.escape("(#{keyword})")
          end.join("+OR+") + ")"
        end.join("+AND+")
        @logger.debug "Entrez scraper initialized with query #{@query}"
      rescue
        # query is not an array of arrays, it must be a list of input_article ids or sids
        @input_articles = query
        @logger.debug "Entrez scraper initialized with #{@input_articles.length} input articles"
      end
    end

    def create_search_url(page)
      retmax = self.class.results_per_page
      retstart = (page - 1) * retmax
      "#{@search_url}&term=#{@query}&retstart=#{retstart}&retmax=#{retmax}&usehistory=y"
    end

    def get_start_page
      url = create_search_url(1)
      page = Typhoeus::Request.get(url, @headers)
      Nokogiri::XML.parse(page.body, URI.escape(url))
    end

    def total_pages(page)
      begin
        results_text = ScraperBase.node_text(page, '/eSearchResult/Count/text()')
        n = results_text.to_i
        raise 'Zero total' if n == 0
        @logger.info("Found total of #{n} results")
        n
      rescue
        'Unknown'
      end
    end

    def get_next_page_link(page, page_id)
      begin
        create_search_url page_id
      rescue
        nil
      end
    end

    def process_list_page(page, &block)
      page = Nokogiri::XML(page.body) unless page.is_a?(Nokogiri::XML::Document)

      @logger.info("Processing list page")

      items = page/'/eSearchResult/IdList/Id'
      @logger.info "Found #{items.length} items in page"
      @hercules_articles.fight(items) do |id|
        pmid = id.text
        @logger.info "Got result with id #{pmid}"
        # get detailed info
        process_detail_page(pmid, &block)
      end # end fight
    end

    def process_detail_page(pmid, extraction_fields = nil, &block)
      mArticle = RayyanFormats::Target.new
      mArticle.sid = pmid
      mArticle.url = "#{@detail_friendly_url}#{pmid}"
      fetch_and_parse_detail_page(pmid, mArticle, extraction_fields, &block)
    end

    def fake_process_detail_page(pmid)
      mArticle = RayyanFormats::Target.new
      mArticle.sid = pmid
      mArticle.url = "#{@detail_friendly_url}/#{pmid}"
      mArticle
    end

    def fetch_and_parse_detail_page(pmid, mArticle, extraction_fields = nil)
      @logger.debug "Requesting detail page as #{pmid}"
      link = "#{@detail_url}&id=#{pmid}"

      @hercules_articles.strike(link, "entrez-#{pmid}", true) do |request, response|
        if response.class == Exception
          yield nil if block_given?
        else
          @logger.debug "Processing detail page as #{pmid}"
          xml = Nokogiri::XML.parse(response, link)
          root = xml.at "/#{@xml_element_root}/#{@xml_element_root_article}"
          unless root.nil?
            process_article_detail_page(root, mArticle, extraction_fields)
            yield mArticle if block_given?
          else
            root = xml.at "/#{@xml_element_root}/#{@xml_element_root_book}"
            unless root.nil?
              process_book_detail_page(root, mArticle, extraction_fields)
              yield mArticle if block_given?
            else
              @logger.warn "Unknown XML format for PMID #{pmid} with url #{link}"
              yield nil if block_given?
            end # unless book
          end # unless article
        end # if exception
      end # strike
    end # def

    def process_article_detail_page(xml, mArticle, extraction_fields = nil)
      # Example: http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id=23185113

      extraction_fields = DEFAULT_EXTRACTION_FIELDS if extraction_fields.nil?
      article_xml = xml/"./#{@xml_element_citation}/Article"
      
      extract_article_title article_xml, mArticle if extraction_fields[:title]
      extract_copyright article_xml, mArticle if extraction_fields[:copyright]
      extract_affiliation article_xml, mArticle if extraction_fields[:affiliation]
      extract_language article_xml, mArticle if extraction_fields[:language]
      extract_pubtypes article_xml, mArticle if extraction_fields[:pubtypes]
      extract_abstracts article_xml, mArticle if extraction_fields[:abstracts]
      extract_authors article_xml, mArticle if extraction_fields[:authors]
      extract_journal_info article_xml, mArticle if extraction_fields[:journal]
      extract_article_idtypes xml, mArticle if extraction_fields[:idtypes]
      extract_mesh xml, mArticle if extraction_fields[:keyphrases]

      # TODO: full text (link out) either from same document (id?) or from 
      # another ELink request: http://www.ncbi.nlm.nih.gov/books/NBK25499/#chapter4.ELink
    end

    def process_book_detail_page(xml, mArticle, extraction_fields = nil)
      # Example: http://www.ncbi.nlm.nih.gov/pubmed?term=22787640

      extraction_fields = DEFAULT_EXTRACTION_FIELDS if extraction_fields.nil?
      bookdoc = xml/'./BookDocument'
      book = bookdoc/'./Book'
      
      extract_book_title book, mArticle if extraction_fields[:title]
      extract_authors book, mArticle if extraction_fields[:authors]
      extract_publisher book, mArticle if extraction_fields[:publisher]
      extract_collection book, mArticle if extraction_fields[:collection]
      extract_date book, './PubDate', mArticle if extraction_fields[:dates]
      extract_book_pubtypes book, mArticle if extraction_fields[:pubtypes]
      extract_copyright bookdoc, mArticle if extraction_fields[:copyright]
      extract_language bookdoc, mArticle if extraction_fields[:language]
      extract_abstracts bookdoc, mArticle if extraction_fields[:abstracts]
      extract_sections bookdoc, mArticle if extraction_fields[:sections]
      extract_book_idtypes xml, mArticle if extraction_fields[:idtypes]
    end

    # not test covered
    def iterate_manual_entries
      @hercules_articles.fight(@input_articles) do |pmid|
        pmid.gsub! /PMC|PMH/, ''
        # fetch it
        process_detail_page(pmid) do |article|
          yield article if block_given?
        end
      end
    end

    # not test covered
    def fetch_and_parse_article_list(list, extraction_fields = nil)
      # list should be an array of objects of format {pmid: pmid, article: RayyanFormats::Target}
      @hercules_articles.fight(list) do |article|
        fetch_and_parse_detail_page(article.sid, article, extraction_fields) do |article|
          yield article if block_given?
        end
      end
    end

    # not test covered
    def fetch_and_parse_pmid_list(list, extraction_fields = nil)
      @hercules_articles.fight(list) do |pmid|
        process_detail_page(pmid, extraction_fields) do |article|
          yield article if block_given?
        end
      end
    end

    # user upload xml
    def parse_search_results(string, extraction_fields = nil)
      xml = Nokogiri::XML.parse(string, "file:///rawfile.xml")
      items = xml/"/#{@xml_element_root}/*"
      total = items.length
      @logger.debug("Found #{total} articles in input pubmed file")
      items.each do |item|
        begin
          mArticle = RayyanFormats::Target.new
          failed = false
          case item.node_name
          when @xml_element_root_article
            process_article_detail_page(item, mArticle, extraction_fields)
          when @xml_element_root_book
            process_book_detail_page(item, mArticle, extraction_fields)
          else
            @logger.warn "Unknown XML format for search result of type #{item.node_name}"
            failed = true
          end

          unless failed
            pmid = ScraperBase.node_text item, './/PMID'
            mArticle.sid = pmid
            mArticle.url = "#{@detail_friendly_url}#{pmid}"
            yield mArticle, total if block_given?
          end # unless failed
        rescue => exception
          @logger.error "Error processing item in search result of type #{item.node_name} [#{exception}] " +
            "caused by #{exception.backtrace.first}"
        end # process item rescue
      end # items.each
      total
    end # def parse_search_results

    def extract_xpath_text(xml, xpath)
      text = (xml/xpath).text
      text.present? ? text : nil
    end

    def extract_article_title(xml, mArticle)
      mArticle.title = extract_xpath_text xml, './ArticleTitle'
    end

    def extract_book_title(xml, mArticle)
      mArticle.title = extract_xpath_text xml, './BookTitle'
    end

    def extract_copyright(xml, mArticle)
      mArticle.copyright = extract_xpath_text xml, './Abstract/CopyrightInformation'
    end

    def extract_affiliation(xml, mArticle)
      mArticle.affiliation = extract_xpath_text xml, './Affiliation'
    end

    def extract_language(xml, mArticle)
      mArticle.language = extract_xpath_text xml, './Language'
    end

    def extract_publisher(xml, mArticle)
      mArticle.publisher_name = extract_xpath_text xml, './Publisher/PublisherName'
      mArticle.publisher_location = extract_xpath_text xml, './Publisher/PublisherLocation'
    end

    def extract_collection(xml, mArticle)
      mArticle.collection = extract_xpath_text xml, './CollectionTitle'
      mArticle.collection_code = extract_xpath_text xml, './CollectionTitle/@book'
    end

    def extract_abstracts(xml, mArticle)
      mArticle.abstracts = (xml/'./Abstract/AbstractText').to_enum.map do |abstract|
        {
          label: abstract['Label'],
          category: abstract['NlmCategory'],
          content: abstract.text
        }
      end
    end

    def extract_authors(xml, mArticle)
      mArticle.authors = (xml/'./AuthorList/Author').to_enum.map do |author|
        lastname = extract_xpath_text(author, './LastName') || extract_xpath_text(author, './CollectiveName')
        firstname = extract_xpath_text(author, './ForeName') || '[Collective Name]'

        "#{lastname}, #{firstname}"        
      end
    end

    def extract_article_idtypes(xml, mArticle)
      extract_idtypes xml, mArticle, "./#{@xml_element_data}/ArticleIdList/ArticleId"
    end

    def extract_book_idtypes(xml, mArticle)
      extract_idtypes xml, mArticle, "./#{@xml_element_bookdata}/ArticleIdList/ArticleId" \
        " | ./BookDocument/ArticleIdList/ArticleId"
    end

    def extract_idtypes(xml, mArticle, xpath)
      mArticle.article_ids = (xml/xpath).to_enum.map do |id|
        idtype = id['IdType']
        idtype = @db_idtype if idtype == @xml_idtype
        value = id.text

        {idtype: idtype, value: value}
      end
    end

    def extract_pubtypes(xml, mArticle)
      mArticle.publication_types = (xml/'./PublicationTypeList/PublicationType').to_enum.map(&:text)
    end

    def extract_book_pubtypes(xml, mArticle)
      mArticle.publication_types = ["Book"]
    end

    def extract_mesh(xml, mArticle)
      mArticle.keyphrases = (xml/"./#{@xml_element_citation}/MeshHeadingList//DescriptorName" \
        " | ./#{@xml_element_citation}/KeywordList/Keyword").to_enum.map(&:text)
    end

    def extract_sections(xml, mArticle)
      mArticle.sections = (xml/'./Sections/Section').to_enum.map do |section|
        sloc = section.at './LocationLabel'
        sloc = "#{sloc['Type']}:#{sloc.text}" unless sloc.nil?
        stitle = section.at './SectionTitle'
        spart = stitle['part']
        stitle = stitle.text 

        {
          code: spart,
          location: sloc,
          title: stitle
        }
      end
    end

    def extract_journal_info(xml, mArticle)
      journal = xml.at './Journal'

      mArticle.journal_title = extract_xpath_text journal, './Title'
      mArticle.journal_issn = extract_xpath_text journal, './ISSN'
      mArticle.journal_abbreviation = extract_xpath_text journal, './ISOAbbreviation'
      mArticle.jvolume = extract_xpath_text(journal, './JournalIssue/Volume').to_i
      mArticle.jissue = extract_xpath_text(journal, './JournalIssue/Issue').to_i
      mArticle.pagination = extract_xpath_text xml, './Pagination/MedlinePgn'

      jdate = extract_date journal, './JournalIssue/PubDate', mArticle

      if jdate.compact.empty?
        jdate = extract_xpath_text journal, './JournalIssue/PubDate/MedlineDate'
        year = jdate.split.first
        month = jdate.split.last.split('-').first
        mArticle.date_array = [year, month]
      end
    end

    def extract_date(xml, xpath, mArticle)
      year = extract_xpath_text xml, "#{xpath}/Year"
      month = extract_xpath_text xml, "#{xpath}/Month"
      day = extract_xpath_text xml, "#{xpath}/Day"
      mArticle.date_array = [year, month, day]
    end

  end # class
end
