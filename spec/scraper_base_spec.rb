require 'spec_helper'

include RayyanScrapers

describe ScraperBase do
  let(:logger) {
    l = Logger.new(STDOUT)
    l.level = Logger::FATAL
    l
  }
  let(:scraper) { ScraperBase.new(logger) }

  describe '.initialize' do
    context 'setting @max_parallel_articles' do
      let(:max_parallel_articles) { 100 }

      before {
        allow(ScraperBase).to receive(:max_parallel_articles) { max_parallel_articles }
      }

      it 'sets @max_parallel_articles' do
        expect(scraper.instance_variable_get('@max_parallel_articles')).to eq(max_parallel_articles)
      end
    end

    it 'sets @logger to specified argument' do
      expect(scraper.instance_variable_get('@logger')).to eq(logger)
    end

    context 'when no logger object is specified in arguments' do
      let(:logger) { nil }

      it 'sets @logger to a new instance of DummyLogger' do
        expect(scraper.instance_variable_get('@logger')).to be_instance_of(DummyLogger)
      end
    end

    it 'sets @hercules_articles to a new instance of Hercules' do
      expect(scraper.instance_variable_get('@hercules_articles')).to be_instance_of(Hercules)
    end
  end

  describe '.scrape' do
    let(:start_page) { double }

    before {
      allow(scraper).to receive(:get_start_page){ start_page }
      allow_any_instance_of(Hercules).to receive(:kill) {|&block|
        block.call(10)
      }
    }

    it 'calls iterate_list_pages with start page' do
      expect(scraper).to receive(:iterate_list_pages).with(start_page)
      scraper.scrape
    end
  end

  describe '#iterate_list_pages' do
    let(:start_page) { double("start_page") }

    before {
      allow(scraper).to receive(:process_list_page)
    }

    context "when start page is nil" do
      it "does nothing" do
        expect(scraper).not_to receive(:process_list_page)
        scraper.iterate_list_pages(nil)
      end
    end

    context "when start page is not nil" do
      context "when no items returned from current page" do
        before {
          expect(scraper).to receive(:process_list_page).with(start_page) { 0 }
        }

        it "does not call process_list_page again" do
          # expected start_page already in before{} and no more
          scraper.iterate_list_pages(start_page)
        end
      end

      context "when some items returned from current page" do
        before {
          expect(scraper).to receive(:process_list_page).with(start_page) { 1 }
        }

        context "when have scraped enough pages" do
          before {
            allow(scraper).to receive(:enough_pages).with(2) { true }
          }

          it "does not call process_list_page again" do
            # expected start_page already in before{} and no more
            scraper.iterate_list_pages(start_page)
          end
        end

        context "when have not scraped enough pages" do
          before {
            allow(scraper).to receive(:enough_pages).with(2) { false }
          }

          it "gets next page link" do
            expect(scraper).to receive(:get_next_page_link).with(start_page, 2)
            scraper.iterate_list_pages(start_page)
          end

          context "when there is a page next" do
            let(:next_page_link) { "next_page_link" }
            let(:next_page_body) { "body" }
            let(:next_page) { Stubber.stub_request_with_body(next_page_body, next_page_link) }

            before {
              allow(scraper).to receive(:get_next_page_link).with(start_page, 2) { next_page_link }
              allow(scraper).to receive(:enough_pages).with(3) { true } # otherwise won't stop
            }

            it "calls process_list_page again on the next page" do
              expect(scraper).to receive(:process_list_page).with(next_page)
              scraper.iterate_list_pages(start_page)
            end
          end

          context "when there is no page next" do
            before {
              allow(scraper).to receive(:get_next_page_link).with(start_page, 2)
            }

            it "does not call process_list_page again" do
              # expected start_page already in before{} and no more
              scraper.iterate_list_pages(start_page)
            end
          end
        end
      end
    end
  end

  describe '#enough_pages' do
    context "when maximum pages is configured" do
      let(:max_pages) { 10 }

      before {
        allow(ScraperBase).to receive(:max_pages_to_scrape){ max_pages }
      }

      context "when page_id is less than to maximum pages" do
        let(:page_id) { max_pages - 1 }

        it "returns false" do
          expect(scraper.enough_pages(page_id)).to eq(false)
        end
      end

      context "when page_id is equal to maximum pages" do
        let(:page_id) { max_pages }

        it "returns false" do
          expect(scraper.enough_pages(page_id)).to eq(false)
        end
      end

      context "when page_id is larger than maximum pages" do
        let(:page_id) { max_pages + 1 }

        it "returns true" do
          expect(scraper.enough_pages(page_id)).to eq(true)
        end
      end
    end

    context "when no maximum pages configured" do
      let(:page_id) { 999999 }

      it "returns false" do
        expect(scraper.enough_pages(page_id)).to eq(false)
      end
    end
  end

  describe '.node_text' do
    context 'valid inputs' do
      html_doc = Nokogiri::HTML("<html><body><h1>node text</h1><h2>hello</h2></body></html>")
      it { expect(ScraperBase.node_text(html_doc, 'h1')).to eq("node text") }
    end
  end

  describe '.node_html' do
    context 'valid inputs'  do
      html_doc = Nokogiri::HTML("<html><body><h1>node html</h1></body></html>")
      it { expect(ScraperBase.node_html(html_doc, '//body')).to eq("<h1>node html</h1>") }
    end
  end

  describe '.max_parallel_articles' do
    context 'when no environment variable set' do
      before {
        ENV['SCRAPERS_MAX_PARALLEL_ARTICLES'] = nil
      }

      it 'returns the default value' do
        expect(ScraperBase.max_parallel_articles).to eq(ScraperBase::DEFAULT_MAX_PARALLEL_ARTICLES)
      end
    end

    context 'when the environment variable is set' do
      let(:max_parallel_articles) { 100 }

      before {
        ENV['SCRAPERS_MAX_PARALLEL_ARTICLES'] = max_parallel_articles.to_s
      }

      it 'returns the environment variable' do
        expect(ScraperBase.max_parallel_articles).to eq(max_parallel_articles)
      end
    end
  end

  describe '.max_pages_to_scrape' do
    it "returns 0" do
      expect(ScraperBase.max_pages_to_scrape).to eq(0)
    end
  end

  describe '.max_results' do
    before {
      allow(ScraperBase).to receive(:max_pages_to_scrape) { 2 }
      allow(ScraperBase).to receive(:results_per_page) { 5 }
    }

    it "returns max_pages_to_scrape * results_per_page" do
      expect(ScraperBase.max_results).to eq(10)
    end
  end

  describe '#total_pages' do
    it "returns Unknown" do
      expect(scraper.total_pages(double)).to eq('Unknown')
    end
  end

  describe 'not implemented methods' do
    let(:args_count) { 0 }
    let(:is_instance_method) { true }

    shared_examples "not_implemented_method" do
      it "raises Not implemented error" do
        object = is_instance_method ? scraper : ScraperBase
        args = [double] * args_count
        expect{
          object.send(method, *args)
        }.to raise_error(RuntimeError, 'Not implemented')
      end
    end

    describe '.results_per_page' do
      let(:method) { :results_per_page }
      let(:is_instance_method) { false }
      it_behaves_like "not_implemented_method"
    end

    describe '#get_start_page' do
      let(:method) { :get_start_page }
      it_behaves_like "not_implemented_method"
    end

    describe '#get_next_page_link' do
      let(:method) { :get_next_page_link }
      let(:args_count) { 2 }
      it_behaves_like "not_implemented_method"
    end

    describe '#process_list_page' do
      let(:method) { :process_list_page }
      let(:args_count) { 1 }
      it_behaves_like "not_implemented_method"
    end

    describe '#get_detail' do
      let(:method) { :get_detail }
      it_behaves_like "not_implemented_method"
    end

    describe '#process_detail_page' do
      let(:method) { :process_detail_page }
      it_behaves_like "not_implemented_method"
    end
  end
end
