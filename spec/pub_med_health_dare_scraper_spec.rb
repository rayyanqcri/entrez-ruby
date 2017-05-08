require 'spec_helper'

include RayyanScrapers

describe PubMedHealthDareScraper do
  let(:scraper) { PubMedHealthDareScraper.new }

  describe ".initialize" do
    it "assigns @search_url" do
      expect(scraper.instance_variable_get(:@search_url)).to eq("http://www.ncbi.nlm.nih.gov/pubmedhealth/s/dare_reviews_medrev")
    end
  end
end
