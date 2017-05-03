require 'spec_helper'

include RayyanScrapers

describe NihFulltextScraper do
  let(:list) { (1..5).to_a }
  let(:nih_fulltext_scraper) { NihFulltextScraper.new(list) }
  let(:base_url) { nih_fulltext_scraper.instance_variable_get(:@base_url) }

  describe "#initialize" do
    it "assigns @base_url" do
      expect(nih_fulltext_scraper.instance_variable_get(:@base_url)).to eq("http://localhost:8000/fromNIH")
    end

    it "assigns @refs_link_name" do
      expect(nih_fulltext_scraper.instance_variable_get(:@refs_link_name)).to eq("pmc_refs_pubmed")
    end
  end

  describe "#create_search_url" do
    context "when page params is 1" do
      it "assigns relative path to DARE" do
        expect(nih_fulltext_scraper.create_search_url(double, 1)).to eq("http://localhost:8000/fromNIH/DARE")
      end
    end

    context "when page params is 2" do
      it "assigns relative path to SYST_REVIEWS_FROM_PUBMED" do
        expect(nih_fulltext_scraper.create_search_url(double, 2)).to eq("http://localhost:8000/fromNIH/SYST_REVIEWS_FROM_PUBMED")
      end
    end

    context "when page params is 3" do
      it "assigns relative path to SYST_REVIEWS_FROM_PMH" do
        expect(nih_fulltext_scraper.create_search_url(double, 3)).to eq("http://localhost:8000/fromNIH/SYST_REVIEWS_FROM_PMH")
      end
    end
  end

  describe ".max_pages_to_scrape" do
    it "returns a staticaly set number" do
      expect(NihFulltextScraper.max_pages_to_scrape).to eq(1)
    end
  end

  describe "#total_pages" do
    it "returns a staticaly set number" do
      expect(nih_fulltext_scraper.total_pages("page")).to eq(0)
    end
  end

  describe "#get_next_page_link" do
    before {
      allow(nih_fulltext_scraper).to receive(:create_search_url)
    }

    it "delegates to create_search_url" do
      expect(nih_fulltext_scraper).to receive(:create_search_url)
      nih_fulltext_scraper.get_next_page_link(double, 1)
    end
  end
end
