require 'spec_helper'

describe BlueHydra do
  it "is a module" do
    expect(BlueHydra.class).to eq(Module)
  end

  it "has a version" do
    expect(BlueHydra::VERSION =~ /\d\.\d\.\d/i).to eq(0)
  end
end
