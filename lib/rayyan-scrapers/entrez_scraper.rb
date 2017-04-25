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

    def initialize(query, content_dir = 'entrez-contents', log_file = 'entrez.log')
      super(log_file, content_dir)

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

      @stop_on_seen_page = false
    end

    def create_search_url(page)
      retmax = self.class.results_per_page
      retstart = (page - 1) * retmax
      "#{@search_url}&term=#{@query}&retstart=#{retstart}&retmax=#{retmax}&usehistory=y"
    end

    def get_start_page
      url = create_search_url(1)
      #page = @agent.get url
      page = Typhoeus::Request.get(url, @headers)
      # @logger.debug(page.body)
      Nokogiri::XML.parse(page.body, URI.escape(url))
    end

    def total_pages(page)
      begin
        results_text = ScraperBase.node_text(page, '/eSearchResult/Count/text()')
        n = results_text.to_i
        @logger.info("Found total of #{n} results")
        n
      rescue
        'Unknown'
      end
    end

    def get_next_page_link(page)
      begin
        create_search_url @curr_page
      rescue
        nil
      end
    end

    def process_list_page(page)
      begin
        page.url  # parsed xml
      rescue
        page = Nokogiri::XML.parse(page.body, page.request.url.to_s)
      end

      @logger.info("Processing list page having URL: #{page.url}")
      #page.save_as "result-list.html"

      new_items_found = nil

      items = page/'/eSearchResult/IdList/Id'
      @logger.info "Found #{items.length} items in page"
      #items.each do |id|
      @hercules_articles.fight(items) do |id|
        new_items_found = false if new_items_found.nil?
        pmid = id.text
        @logger.info "Got result with id #{pmid}"
        # get detailed info
        begin
          article = Article.find_by_sid(pmid)
          if article.nil?
            new_items_found = true
            process_detail_page(pmid) do |article|
              @logger.info "  Item #{@curr_property} of #{@total}..."
              yield article, true if block_given?
            end
          else
            @logger.info "  Item #{@curr_property} of #{@total}..."
            yield article, false if block_given?
          end
        # rescue => exception
        #   @logger.error "Error processing #{pmid}:"
        #   @logger.error exception
        #   @logger.error exception.backtrace.join("\n")
        end
        @curr_property = @curr_property + 1
      end # end fight
      new_items_found
    end

    def self.extract_abstracts(xml, mArticle)
      mArticle.abstracts.clear
      (xml/'./Abstract/AbstractText').each do |abstract|
        mArticle.abstracts.build  :label => abstract['Label'],
                                  :category => abstract['NlmCategory'],
                                  :content => abstract.text
      end
    end

    def self.extract_authors(xml, mArticle)
      mArticle.authors.clear
      (xml/'./AuthorList/Author').to_enum.each.with_index do |author, index|
        lastname = ScraperBase.node_text(author, './LastName') || ScraperBase.node_text(author, './CollectiveName')
        firstname = ScraperBase.node_text(author, './ForeName') || '[Collective Name]'
        initials = ScraperBase.node_text author, './Initials'

        mArticle.authors << Author.where(:firstname => firstname, :lastname => lastname).first_or_initialize do |mAuthor|
          mAuthor.initials = initials
        end
        mArticle.update_last_author_order(index)
      end
    end

    def self.extract_idtypes(xml, mArticle, xpath)
      mArticle.article_ids.clear
      (xml/xpath).each do |id|
        idtype = id['IdType']
        idtype = @db_idtype if idtype == @xml_idtype
        value = id.text
        mArticle.article_ids.build :idtype => idtype, :value => value
      end
    end

    def self.extract_date(xml, xpath)
      year = xml.at("#{xpath}/Year/text()")
      month = xml.at("#{xpath}/Month/text()")
      day = xml.at("#{xpath}/Day/text()")
      ScraperBase.to_date year, month, day
    end

    def self.extract_pubtypes(xml, mArticle, logger)
      pubtypes = mArticle.publication_types.map(&:name)
      (xml/'./PublicationTypeList/PublicationType/text()').each do |pubtype|
        pubtype = pubtype.to_s.strip
        mPubtype = PublicationType.where(name: pubtype).first_or_initialize
        mArticle.publication_types << mPubtype unless pubtypes.include?(pubtype)
      end
    end

    def self.extract_mesh(xml, mArticle, logger)
      keyphrases = mArticle.keyphrases.map(&:name)
      (xml/"./MeshHeadingList//DescriptorName | ./#{@xml_element_citation}/KeywordList/Keyword").each do |mesh|
        mesh = mesh.text.strip
        mKeyphrase = Keyphrase.where(name: mesh).first_or_initialize
        mArticle.keyphrases << mKeyphrase unless keyphrases.include?(mesh)
      end
    end

    def self.extract_publisher(xml, mArticle)
      pname = (xml/'./Publisher/PublisherName').text
      ploc = (xml/'./Publisher/PublisherLocation').text
      mArticle.publisher = Publisher.where(name: pname).first_or_initialize do |mPublisher|
        mPublisher.location = ploc
      end
    end

    def self.extract_collection(xml, mArticle)
      ccode = (xml/'./CollectionTitle/@book').text
      ctitle = (xml/'./CollectionTitle').text
      mArticle.collection = Collection.where(code: ccode).first_or_initialize do |mCollection|
        mCollection.title = ctitle
      end
    end

    def self.extract_sections(xml, mArticle)
      (xml/'./Sections/Section').each do |section|
        sloc = section.at './LocationLabel'
        sloc = "#{sloc['Type']}:#{sloc.text}" unless sloc.nil?
        stitle = section.at './SectionTitle'
        spart = stitle['part']
        stitle = stitle.text 

        mArticle.sections.build  :code => spart,
                                  :location => sloc,
                                  :title => stitle
      end
    end

    def process_article_detail_page(xml, article_xml, mArticle, extraction_fields = nil)
      # Example: http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id=23185113

      extraction_fields = DEFAULT_EXTRACTION_FIELDS if extraction_fields.nil?
      
      mArticle.title = (article_xml/'./ArticleTitle').text if extraction_fields[:title]
      mArticle.copyright = (article_xml/'./Abstract/CopyrightInformation').text if extraction_fields[:copyright]
      mArticle.affiliation = (article_xml/'./Affiliation').text if extraction_fields[:affiliation]
      mArticle.language = (article_xml/'./Language').text if extraction_fields[:language]
      #locid = article_xml/'./ELocationID/text().text'  # most of the time missing + redundant
      #loctype = article_xml/'./ELocationID/@EIdType'

      # Creation date is not necessarily the same as publication date
      mArticle.article_date = EntrezScraper.extract_date(article_xml, './ArticleDate') if extraction_fields[:dates]
      mArticle.screated_at = EntrezScraper.extract_date xml, "./#{@xml_element_citation}/DateCreated" if extraction_fields[:dates]
      
      EntrezScraper.extract_pubtypes article_xml, mArticle, @logger if extraction_fields[:pubtypes]
      EntrezScraper.extract_abstracts article_xml, mArticle if extraction_fields[:abstracts]
      EntrezScraper.extract_authors article_xml, mArticle if extraction_fields[:authors]
      EntrezScraper.extract_idtypes xml, mArticle, "./#{@xml_element_data}/ArticleIdList/ArticleId" if extraction_fields[:idtypes]
      EntrezScraper.extract_mesh xml/"./#{@xml_element_citation}", mArticle, @logger if extraction_fields[:keyphrases]
      
      # TODO: full text (link out) either from same document (id?) or from 
      # another ELink request: http://www.ncbi.nlm.nih.gov/books/NBK25499/#chapter4.ELink

    end

    def process_book_detail_page(xml, mArticle, extraction_fields = nil)
      # Example: http://www.ncbi.nlm.nih.gov/pubmed?term=22787640

      extraction_fields = DEFAULT_EXTRACTION_FIELDS if extraction_fields.nil?
      
      bookdoc = xml/'./BookDocument'
      book = bookdoc/'./Book'
      
      mArticle.title = (book/'./BookTitle').text if extraction_fields[:title]
      mArticle.language = (bookdoc/'./Language').text if extraction_fields[:language]
      mArticle.copyright = (bookdoc/'./Abstract/CopyrightInformation').text if extraction_fields[:copyright]
      mArticle.publication_types << PublicationType.where(name: "Book").first_or_initialize

      mArticle.article_date = EntrezScraper.extract_date book, './PubDate' if extraction_fields[:dates]

      EntrezScraper.extract_abstracts bookdoc, mArticle if extraction_fields[:abstracts]

      EntrezScraper.extract_authors book, mArticle if extraction_fields[:authors]
      EntrezScraper.extract_idtypes xml, mArticle,
        "./#{@xml_element_bookdata}/ArticleIdList/ArticleId" \
        " | ./BookDocument/ArticleIdList/ArticleId" if extraction_fields[:idtypes]
      EntrezScraper.extract_publisher book, mArticle if extraction_fields[:publisher]
      EntrezScraper.extract_collection book, mArticle if extraction_fields[:collection]
      EntrezScraper.extract_sections bookdoc, mArticle if extraction_fields[:sections]
    end

    def process_detail_page(pmid, extraction_fields = nil)
      mArticle = Article.new
      mArticle.source = @source
      mArticle.sid = pmid
      mArticle.url = "#{@detail_friendly_url}#{pmid}"
      fetch_and_parse_detail_page(pmid, mArticle, extraction_fields) do |mArticle|
        mArticle.try :save
        yield mArticle if block_given?
      end
    end

    def fetch_and_parse_detail_page(pmid, mArticle, extraction_fields = nil)
      @logger.debug "Requesting detail page as #{pmid}"
      link = "#{@detail_url}&id=#{pmid}"
      #page = http_get link
      #page = @agent.get link
      # TODO: raising inside a fiber won't call the rescue block!
      #raise page if page.class == Exception
      #return nil if page.class == Exception
      #@logger.debug "Processing detail page as #{pmid} (status code is #{page.response_header.status})"

      @hercules_articles.strike(link, "#{@content_dir}/entrez-#{pmid}.html", true) do |request, response|
        if response.class == Exception
          yield nil if block_given?
        else
          @logger.debug "Processing detail page as #{pmid}"

          #xml = Nokogiri::XML.parse(page.response, link)
          #xml = Nokogiri::XML.parse(page.body, link)
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

    # NOTUSED by islam
    def fake_process_detail_page(pmid)
      mArticle = Article.new
      mArticle.source = @source
      mArticle.sid = pmid
      mArticle.url = "#{@detail_friendly_url}/#{pmid}"
      mArticle.save
      mArticle
    end

    def iterate_input_items(search_type = :ref)
      @total = 0
      if search_type == :ref
        associtation = "references"
        linkname = @refs_link_name
      elsif search_type == :cited
        associtation = "citations"
        linkname = @cited_link_name
      end
      outdated_if_before = Time.now - ENV['REFERENCE_FETCHING_OUTDATED_AFTER_DAYS'].to_i.days
      #@input_articles.each do |pmid|
      @logger.debug "Getting #{associtation} for articles: #{@input_articles}"
      @hercules_refpages.fight(@input_articles) do |input_article|
        if input_article.instance_of? Article
          raise 'NOT IMPLEMENTED YET, should first find article on PubMed from its title/year' if input_article.source != @source
          pmid = input_article.sid
          article_from = input_article
        else
          pmid = "#{input_article}"
          article_from = Article.where(sid: pmid, source_id: @source.id).first
        end
        unless article_from.nil?
          fetched_at = article_from.send("fetched_#{associtation}_at")
          if fetched_at.nil? || fetched_at < outdated_if_before
            article_from.send(associtation).clear
            pmid.gsub! 'PMC', ''  if pmid.class == String # in case sid contains PMC
            pmid.gsub! 'PMH', ''  if pmid.class == String # in case sid contains PMH
            link = "#{@refs_url}&id=#{pmid}&linkname=#{linkname}"
            begin
              process_ref_page(link, pmid, search_type, linkname) do |article, isnew|
                article_from.send(associtation) << article
                yield article, isnew if block_given?
              end
              article_from.send("fetched_#{associtation}_at=", Time.now)
              article_from.save
            rescue => exception
              @logger.error "Error processing #{link}:"
              @logger.error exception
              @logger.error exception.backtrace.join("\n")
            end
          end
        else
          @logger.warn "Trying to fetch refs for a non-existing article having sid #{pmid}"
        end
      end
    end

    def process_ref_page(link, input_pmid, search_type, linkname)
      @logger.debug "Requesting refs page at #{link}"
      #page = http_get link
      #page = @agent.get link
      ## TODO: raising inside a fiber won't call the rescue block!
      #raise page if page.class == Exception
      #return nil if page.class == Exception

      @hercules_refpages.strike(link, "#{@content_dir}/#{search_type}-for-#{input_pmid}.html") do |request, response|
        @logger.debug "Processing refs page at #{link}"
        ## TODO HANDLE HTTP ERRORS
        #xml = Nokogiri::XML.parse(page.response, link)
        #xml = Nokogiri::XML.parse(page.body, link)
        xml = Nokogiri::XML.parse(response, link)
        linksets =  (xml/"//eLinkResult/LinkSet/LinkSetDb[./LinkName='#{linkname}']") || []
        total_linksets = linksets.length
        
        raise "#{input_pmid} has no #{search_type == :ref ? 'references' : 'citations'}!" if total_linksets == 0

        linkset_id = 0
        linksets.each do |linkset|
          linkset_id = linkset_id + 1
          @logger.info "Processing linkset (#{linkname}) #{linkset_id} of #{total_linksets}"
          links = (linkset/'./Link/Id')
          links_count = links.length
          link_id = 0
          #links.each do |linkid|
          @hercules_articles.fight(links) do |linkid|
            link_id = link_id + 1
            pmid = linkid.text

            @logger.info "Got link result with id #{pmid}"

            unless "#{input_pmid}" == "#{pmid}"
              @total += 1
              # get detailed info
              begin
                article = Article.find_by_sid(pmid)
                # TODO: DESTROY OR SKIP?
                #article.destroy unless article.nil?
                if article.nil?
                  #article = fake_process_detail_page(pmid)
                  process_detail_page(pmid) do |article|
                    @logger.debug "  Link (#{pmid}) #{link_id} of #{links_count}"        
                    yield article, true if block_given?
                  end
                else
                  @logger.debug "  Link (#{pmid}) #{link_id} of #{links_count}"        
                  yield article, false if block_given?
                end
              rescue => exception
                @logger.error "Error processing #{pmid}:"
                @logger.error exception
                @logger.error exception.backtrace.join("\n")
              end
            end
          end
        end
      end
    end

    def iterate_manual_entries
      @total = @input_articles.length
      @hercules_articles.fight(@input_articles) do |pmid|
        pmid.gsub! /PMC|PMH/, ''
        article = Article.find_by_sid pmid
        unless article.nil?
          # insert it
          yield article, false if block_given?
        else
          # fetch it
          process_detail_page(pmid) do |article|
            yield article, true if block_given?
          end
        end
      end
    end

    def fetch_and_parse_article_list(list, extraction_fields = nil)
      # list should be an array of objects of format {pmid: pmid, article: Article}
      @hercules_articles.fight(list) do |article|
        fetch_and_parse_detail_page(article.sid, article, extraction_fields) do |article|
          article.save
          yield article if block_given?
        end
      end
    end

    def fetch_and_parse_pmid_list(list, extraction_fields = nil)
      @hercules_articles.fight(list) do |pmid|
        process_detail_page(pmid, extraction_fields) do |article|
          yield article if block_given?
        end
      end
    end

    #user upload xml
    def parse_search_results(string, extraction_fields = nil)
      xml = Nokogiri::XML.parse(string, "file:///rawfile.xml")
      items = xml/"/#{@xml_element_root}/*"
      total = items.length
      @logger.debug("Found #{total} articles in input pubmed file")
      items.each do |item|
        begin
          mArticle = Article.new
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
            # save only if new
            pmid = ScraperBase.node_text item, './/PMID'
            existing = Article.where(sid: pmid, source_id: @source.id).first
            if existing.nil?
              mArticle.source = @source
              mArticle.sid = pmid
              mArticle.url = "#{@detail_friendly_url}#{pmid}"
              mArticle.save
              @logger.debug("Inserted new article #{mArticle.id}:#{mArticle.title}")
              yield mArticle, true, total if block_given?
            else
              @logger.debug("Found existing article #{existing.id}:#{existing.title}")
              yield existing, false, total if block_given?
            end
          end # unless failed
        rescue => exception
          @logger.error "Error processing item in search result of type #{item.node_name}:"
          @logger.error exception
          @logger.error exception.backtrace.join("\n")
        end # process item rescue
      end # items.each
      total
    end # def parse_search_results
  end # class
end
