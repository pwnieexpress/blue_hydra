require 'spec_helper'

describe BtMon do
  it "is a module" do
    expect(BtMon.class).to eq(Module)
  end

  it "has a version" do
    expect(BtMon::VERSION =~ /\d\.\d\.\d/i).to eq(0)
  end
end
