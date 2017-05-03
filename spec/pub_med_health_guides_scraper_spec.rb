require 'spec_helper'

include RayyanScrapers

describe PubMedHealthGuidesScraper do
  let(:scraper) { PubMedHealthGuidesScraper.new("query") }

  describe ".initialize" do
    it "assigns @search_url" do
      expect(scraper.instance_variable_get(:@search_url)).to eq("http://www.ncbi.nlm.nih.gov/pubmedhealth/s/clinical_guides_medrev")
    end
  end
end
