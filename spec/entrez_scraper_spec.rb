require 'spec_helper'

include RayyanScrapers

describe EntrezScraper do
  let(:logger) {
    l = Logger.new(STDOUT)
    l.level = Logger::FATAL
    l
  }
  let(:query) { (1..5).map{|i| "title#{i}"} }
  let(:entrez_scraper) { EntrezScraper.new(query, logger) }
  let(:contents_path) { Pathname.new "spec/support/entrez-contents" }
  let(:article) { RayyanFormats::Target.new }

  before do
    allow_any_instance_of(Hercules).to receive(:enable_cache).and_return(true)
    entrez_scraper.instance_variable_set(:@xml_element_root, "ArticleSet")
    entrez_scraper.instance_variable_set(:@xml_element_root_article, "Article")
    entrez_scraper.instance_variable_set(:@xml_element_citation, "Element")
    entrez_scraper.instance_variable_set(:@xml_element_root_book, "Book")
  end

  describe "#initialize" do
    context "when query param is an array" do
      it "assigns @input_articles to query param" do
        expect(entrez_scraper.instance_variable_get("@input_articles")).to be(query)
      end

      it "assigns @query to nil" do
        expect(entrez_scraper.instance_variable_get("@query")).to be_nil
      end
    end

    context "when query param is an array of arrays" do
      let(:query) { [['k1', 'j2'], ['k3', 'j4'], ['k5', 'j6']] }

      it "assigns @input_articles to nil" do
        expect(entrez_scraper.instance_variable_get("@input_articles")).to be(nil)
      end

      it "assigns @query to the product of sums for the query" do
        expect(entrez_scraper.instance_variable_get("@query")).to \
          eq("((k1)+OR+(j2))+AND+((k3)+OR+(j4))+AND+((k5)+OR+(j6))")
      end
    end
  end

  describe "#create_search_url" do
    it "raises an error when called on the abstract class" do
      expect(lambda{ entrez_scraper.create_search_url(3) }).to \
        raise_error(RuntimeError, /Not implemented/)
    end

    it "returns string url assuming a child class implements the results_per_page method" do
      allow(EntrezScraper).to receive(:results_per_page).and_return(10)
      entrez_scraper.instance_variable_set(:@search_url, "http://test_url?x=y")
      entrez_scraper.instance_variable_set(:@query, "query")

      expect(entrez_scraper.create_search_url(3)).to \
        eq("http://test_url?x=y&term=query&retstart=20&retmax=10&usehistory=y")
    end
  end

  describe "#get_start_page" do
    let(:start_url) { "http://www.start_url.com" }
    let(:body) { "body" }
    let(:parsed) { double }

    before {
      allow(entrez_scraper).to receive(:create_search_url).with(1){ start_url }
      Stubber.stub_request_with_body(body, start_url)
      allow(Nokogiri::XML).to receive(:parse).with(body, start_url) { parsed }
    }

    it "returns a parsed Nokogiri object for the start page" do
      expect(entrez_scraper.get_start_page).to be(parsed)
    end
  end

  describe "#total_pages" do
    let(:page) { double }

    context "when page param is not a Nokogiri object" do
      before {
        allow(ScraperBase).to receive(:node_text).with(page, anything){ raise RuntimeError }
      }

      it "returns Unknown" do
        expect(entrez_scraper.total_pages(page)).to eq("Unknown")
      end
    end

    context "when page param is a Nokogiri object" do
      context "when page has the total xpath" do
        before {
          allow(ScraperBase).to receive(:node_text).with(page, anything) { "10" }
        }

        it "returns the correct total" do
          expect(entrez_scraper.total_pages(page)).to eq(10)
        end
      end

      context "when page has the total xpath but not a number" do
        before {
          allow(ScraperBase).to receive(:node_text).with(page, anything) { "x" }
        }

        it "returns Unknown" do
          expect(entrez_scraper.total_pages(page)).to eq("Unknown")
        end
      end

      context "when page does not have the total xpath" do
        before {
          allow(ScraperBase).to receive(:node_text).with(page, anything) { nil }
        }

        it "returns Unknown" do
          expect(entrez_scraper.total_pages(page)).to eq("Unknown")
        end
      end
    end
  end

  describe "#get_next_page_link" do
    let(:url) { double }

    it "returns nil when create_search_url raises an error" do
      allow(entrez_scraper).to receive(:create_search_url) { raise RuntimeError }
      expect(entrez_scraper.get_next_page_link(double, double)).to be_nil
    end

    it "delegates return value to create_search_url" do
      allow(entrez_scraper).to receive(:create_search_url) { url }
      expect(entrez_scraper.get_next_page_link(double, double)).to be(url)
    end
  end

  describe "#process_list_page" do
    let(:body) { File.open(contents_path.join("entrez-test.log")) }
    let(:response) { Typhoeus::Response.new(code: 200, body: body) }
    let(:page) { Nokogiri::XML(body) }

    before {
      (1..5).each{|i| expect(entrez_scraper).to receive(:process_detail_page).with(i.to_s) }
    }

    it "parses the page if not parsed already" do
      entrez_scraper.process_list_page(response)
    end

    it "calls process_detail_page for each entry in the list" do
      entrez_scraper.process_list_page(page)
    end
  end

  describe "#process_detail_page" do
    let(:pmid) { 100 }

    it "delegates to fetch_and_parse_detail_page" do
      expect(entrez_scraper).to receive(:fetch_and_parse_detail_page) {|arg1, arg2, arg3|
        expect(arg1).to eq(pmid)
        expect(arg2.class).to eq(RayyanFormats::Target)
        expect(arg2.sid).to eq(pmid)
      }
      entrez_scraper.process_detail_page(pmid)
    end
  end

  describe "#fake_process_detail_page" do
    let(:pmid) { 100 }

    it "returns article with given pmid" do
      article = entrez_scraper.fake_process_detail_page(pmid)
      expect(article.class).to eq(RayyanFormats::Target)
      expect(article.sid).to eq(pmid)
    end
  end

  describe "#fetch_and_parse_detail_page" do
    let(:hercules) { entrez_scraper.instance_variable_get("@hercules_articles") }
    let(:detail_url) { "http://detail_url" }
    let(:pmid) { 100 }
    let(:link) { "#{detail_url}&id=#{pmid}" }
    let(:cache_key) { "entrez-#{pmid}" }
    let(:article) { double }
    let(:fields) { double }

    before {
      entrez_scraper.instance_variable_set("@detail_url", detail_url)
      entrez_scraper.instance_variable_set("@xml_element_root", "Root")
      entrez_scraper.instance_variable_set("@xml_element_root_article", "Article")
      entrez_scraper.instance_variable_set("@xml_element_root_book", "Book")
      hercules.instance_variable_set("@max_hydra_queue_length", 0) # no queuing
    }

    context "when error fetching page" do
      before {
        Stubber.stub_request_with_error(400, link)
      }

      it "yields nil" do
        expect{|b| entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields, &b)}.to \
          yield_with_args(nil)
      end
    end

    context "when page schema is article" do
      before {
        Stubber.stub_request_with_file(contents_path.join("entrez-article.xml"), link)
        allow(entrez_scraper).to receive(:process_article_detail_page)
      }

      it "delegates to process_article_detail_page" do
        expect(entrez_scraper).to receive(:process_article_detail_page).with(Nokogiri::XML::Element, article, fields)
        entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields)
      end

      it "yields article" do
        expect{|b| entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields, &b)}.to \
          yield_with_args(article)
      end
    end

    context "when page schema is book" do
      before {
        Stubber.stub_request_with_file(contents_path.join("entrez-book.xml"), link)
        allow(entrez_scraper).to receive(:process_book_detail_page)
      }

      it "delegates to process_book_detail_page" do
        expect(entrez_scraper).to receive(:process_book_detail_page).with(Nokogiri::XML::Element, article, fields)
        entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields)
      end

      it "yields article" do
        expect{|b| entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields, &b)}.to \
          yield_with_args(article)
      end
    end

    context "when page schema is unknown" do
      before {
        Stubber.stub_request_with_file(contents_path.join("entrez-unknown.xml"), link)
      }

      it "yields nil" do
        expect{|b| entrez_scraper.fetch_and_parse_detail_page(pmid, article, fields, &b)}.to \
          yield_with_args(nil)
      end
    end
  end

  describe "#process_article_detail_page" do
    let(:article) { double }
    let(:xml) { double }

    before {
      allow(xml).to receive(:/){ xml }
    }

    context "when specifying extractors" do
      let(:extractors) { {title: 1, copyright: 1, language: 1} }

      it "delegates to specified extractors" do
        expect(entrez_scraper).to receive(:extract_article_title)
        expect(entrez_scraper).to receive(:extract_copyright)
        expect(entrez_scraper).to receive(:extract_language)

        expect(entrez_scraper).not_to receive(:extract_affiliation)
        expect(entrez_scraper).not_to receive(:extract_pubtypes)
        expect(entrez_scraper).not_to receive(:extract_abstracts)
        expect(entrez_scraper).not_to receive(:extract_authors)
        expect(entrez_scraper).not_to receive(:extract_journal_info)
        expect(entrez_scraper).not_to receive(:extract_date)
        expect(entrez_scraper).not_to receive(:extract_article_idtypes)
        expect(entrez_scraper).not_to receive(:extract_mesh)
        expect(entrez_scraper).not_to receive(:extract_date)

        entrez_scraper.process_article_detail_page(xml, article, extractors)
      end
    end

    context "when not specifying any extractors" do
      let(:extractors) { nil }

      it "delegates to all extractors" do
        expect(entrez_scraper).to receive(:extract_article_title)
        expect(entrez_scraper).to receive(:extract_copyright)
        expect(entrez_scraper).to receive(:extract_affiliation)
        expect(entrez_scraper).to receive(:extract_language)
        expect(entrez_scraper).to receive(:extract_pubtypes)
        expect(entrez_scraper).to receive(:extract_abstracts)
        expect(entrez_scraper).to receive(:extract_authors)
        expect(entrez_scraper).to receive(:extract_journal_info)
        expect(entrez_scraper).to receive(:extract_article_idtypes)
        expect(entrez_scraper).to receive(:extract_mesh)

        entrez_scraper.process_article_detail_page(xml, article, extractors)
      end
    end
  end

  describe "#process_book_detail_page" do
    let(:article) { double }
    let(:xml) { double }

    before {
      allow(xml).to receive(:/){ xml }
    }

    context "when specifying extractors" do
      let(:extractors) { {title: 1, copyright: 1, language: 1} }

      it "delegates to specified extractors" do
        expect(entrez_scraper).to receive(:extract_book_title)
        expect(entrez_scraper).to receive(:extract_copyright)
        expect(entrez_scraper).to receive(:extract_language)

        expect(entrez_scraper).not_to receive(:extract_authors)
        expect(entrez_scraper).not_to receive(:extract_publisher)
        expect(entrez_scraper).not_to receive(:extract_collection)
        expect(entrez_scraper).not_to receive(:extract_date)
        expect(entrez_scraper).not_to receive(:extract_book_pubtypes)
        expect(entrez_scraper).not_to receive(:extract_abstracts)
        expect(entrez_scraper).not_to receive(:extract_sections)
        expect(entrez_scraper).not_to receive(:extract_book_idtypes)

        entrez_scraper.process_book_detail_page(xml, article, extractors)
      end
    end

    context "when not specifying any extractors" do
      let(:extractors) { nil }

      it "delegates to all extractors" do
        expect(entrez_scraper).to receive(:extract_book_title)
        expect(entrez_scraper).to receive(:extract_copyright)
        expect(entrez_scraper).to receive(:extract_language)
        expect(entrez_scraper).to receive(:extract_authors)
        expect(entrez_scraper).to receive(:extract_publisher)
        expect(entrez_scraper).to receive(:extract_collection)
        expect(entrez_scraper).to receive(:extract_date)
        expect(entrez_scraper).to receive(:extract_book_pubtypes)
        expect(entrez_scraper).to receive(:extract_abstracts)
        expect(entrez_scraper).to receive(:extract_sections)
        expect(entrez_scraper).to receive(:extract_book_idtypes)

        entrez_scraper.process_book_detail_page(xml, article, extractors)
      end
    end
  end

  describe "#parse_search_results" do
    let(:body) { File.read(contents_path.join "articles.xml") }
    let(:total) { 6 }
    let(:articles_count) { 3 }
    let(:books_count) { 2 }
    let(:unknown_count) { 1 }
    let(:articles_books_count) { 5 }

    before {
      allow(entrez_scraper).to receive(:process_article_detail_page)
      allow(entrez_scraper).to receive(:process_book_detail_page)
    }

    context "when items are articles" do
      it "delegates to process_article_detail_page" do
        expect(entrez_scraper).to receive(:process_article_detail_page).exactly(articles_count).times
        entrez_scraper.parse_search_results(body)
      end
    end

    context "when items are books" do
      it "delegates to process_book_detail_page" do
        expect(entrez_scraper).to receive(:process_book_detail_page).exactly(books_count).times
        entrez_scraper.parse_search_results(body)
      end
    end

    context "when items are unknown" do
      it "skips processing and logs a warning message" do
        expect(logger).to receive(:warn).with(/^Unknown XML/).exactly(unknown_count).times
        entrez_scraper.parse_search_results(body)
      end
    end

    it "yields processed articles/books with total" do
      expect{|b| entrez_scraper.parse_search_results(body, &b)}.to \
        yield_successive_args(*
          [[RayyanFormats::Target, total]] * articles_books_count
        )
    end

    it "returns total items count in file" do
      expect(entrez_scraper.parse_search_results(body)).to eq(total)
    end

    context "when the processing methods raises an exception" do
      before {
        allow(entrez_scraper).to receive(:process_book_detail_page){ raise 'some error' }
      }

      it "rescues the exception" do
        expect{entrez_scraper.parse_search_results(body)}.not_to raise_error
      end

      it "logs the exception" do
        expect(logger).to receive(:error).with(/^Error processing item/).exactly(books_count).times
        entrez_scraper.parse_search_results(body)
      end

      it "yields processed articles/books without the failing ones" do
        expect{|b| entrez_scraper.parse_search_results(body, &b)}.to \
          yield_successive_args(*
            [[RayyanFormats::Target, total]] * (articles_books_count - books_count)
          )
      end
    end
  end

  describe "#extract_*" do
    let(:xml) { double }
    let(:text) { "text here" }

    before {
      allow(entrez_scraper).to receive(:extract_xpath_text).with(xml, String) { text }
    }

    describe "#extract_xpath_text" do
      let(:body) { "<path><to><text>text here</text></to></path>" }
      let(:xml) { Nokogiri::XML.parse(body) }
      let(:xpath) { "/path/to/text" }

      before {
        allow(entrez_scraper).to receive(:extract_xpath_text).and_call_original
      }

      it "returns text content from a given xml document and an xpath" do
        expect(entrez_scraper.extract_xpath_text(xml, xpath)).to eq(text)
      end

      it "returns nil if xpath cannot be found in xml document" do
        expect(entrez_scraper.extract_xpath_text(xml, '/foo/bar')).to eq(nil)
      end
    end

    describe "#extract_article_title" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_article_title(xml, article)}.to \
          change{article.title}.to text
      end
    end

    describe "#extract_book_title" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_book_title(xml, article)}.to \
          change{article.title}.to text
      end
    end

    describe "#extract_copyright" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_copyright(xml, article)}.to \
          change{article.copyright}.to text
      end
    end

    describe "#extract_affiliation" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_affiliation(xml, article)}.to \
          change{article.affiliation}.to text
      end
    end

    describe "#extract_language" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_language(xml, article)}.to \
          change{article.language}.to text
      end
    end

    describe "#extract_publisher" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_publisher(xml, article)}.to \
          change{[article.publisher_name, article.publisher_location]}.to [text, text]
      end
    end

    describe "#extract_collection" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_collection(xml, article)}.to \
          change{[article.collection, article.collection_code]}.to [text, text]
      end
    end

    describe "#extract_abstracts" do
      let(:body) { File.read(contents_path.join("abstracts.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { (1..3).map{|i| {label: "label#{i}", category: "category#{i}", content: "abstract#{i}"}} }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_abstracts(xml, article)}.to \
          change{article.abstracts}.to array
      end
    end

    describe "#extract_authors" do
      let(:body) { File.read(contents_path.join("authors.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { (1..2).map{|i| "a#{i}l, a#{i}f" } << "a3l, [Collective Name]" }

      before {
        allow(entrez_scraper).to receive(:extract_xpath_text).and_call_original
      }
      
      it "assigns extracted text" do
        expect{entrez_scraper.extract_authors(xml, article)}.to \
          change{article.authors}.to array
      end
    end

    describe "#extract_article_idtypes" do
      let(:body) { File.read(contents_path.join("article-idtypes.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { (1..3).map{|i| {idtype: "idtype#{i}", value: "value#{i}"}} }

      before {
        entrez_scraper.instance_variable_set("@xml_element_data", "Data")
      }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_article_idtypes(xml, article)}.to \
          change{article.article_ids}.to array
      end
    end

    describe "#extract_book_idtypes" do
      let(:body) { File.read(contents_path.join("book-idtypes.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Book') }
      let(:array) { (1..3).map{|i| {idtype: "idtype#{i}", value: "value#{i}"}} }

      before {
        entrez_scraper.instance_variable_set("@xml_element_bookdata", "Data")
      }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_book_idtypes(xml, article)}.to \
          change{article.article_ids}.to array
      end
    end

    describe "#extract_pubtypes" do
      let(:body) { File.read(contents_path.join("pubtypes.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { (1..3).map{|i| "pubtype#{i}" } }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_pubtypes(xml, article)}.to \
          change{article.publication_types}.to array
      end
    end

    describe "#extract_book_pubtypes" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_book_pubtypes(nil, article)}.to \
          change{article.publication_types}.to ["Book"]
      end
    end

    describe "#extract_mesh" do
      let(:body) { File.read(contents_path.join("mesh.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { (1..3).map{|i| "mesh#{i}" } }

      before {
        entrez_scraper.instance_variable_set("@xml_element_citation", "Citation")
      }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_mesh(xml, article)}.to \
          change{article.keywords}.to array
      end
    end

    describe "#extract_sections" do
      let(:body) { File.read(contents_path.join("sections.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }
      let(:array) { [
        {code: 'code1', location: 'type1:loc1', title: 'title1'},
        {code: nil, location: ':loc2', title: 'title2'},
        {code: nil, location: nil, title: 'title3'},
      ] }

      it "assigns extracted text" do
        expect{entrez_scraper.extract_sections(xml, article)}.to \
          change{article.sections}.to array
      end
    end

    describe "#extract_journal_info" do
      let(:body) { File.read(contents_path.join("journal.xml")) }
      let(:xml) { Nokogiri::XML.parse(body).at('/Article') }

      before {
        allow(entrez_scraper).to receive(:extract_xpath_text).and_call_original
      }

      context "when journal has publication date (not Medline publication date)" do
        it "assigns extracted text" do
          expect{entrez_scraper.extract_journal_info(xml, article)}.to \
            change{[
              article.journal_title,
              article.journal_issn,
              article.journal_abbreviation,
              article.jvolume,
              article.jissue,
              article.pagination,
              article.date_array
            ]}.to [
              "title1",
              "issn1",
              "abbrev1",
              10,
              1,
              "pages1",
              ["2017", "4", "1"]
            ]
        end
      end

      context "when journal has no publication date (but Medline publication date)" do
        before {
          allow(entrez_scraper).to receive(:extract_date){ [nil] * 3}
        }

        it "assigns extracted text" do
          expect{entrez_scraper.extract_journal_info(xml, article)}.to \
            change{[
              article.date_array
            ]}.to [
              ["1999", "Jan"]
            ]
        end
      end
    end

    describe "#extract_date" do
      it "assigns extracted text" do
        expect{entrez_scraper.extract_date(xml, 'xpath', article)}.to \
          change{article.date_array}.to [text] * 3
      end

      it "returns data array" do
        expect(entrez_scraper.extract_date(xml, 'xpath', article)).to eq([text] * 3)
      end
    end

  end

end
