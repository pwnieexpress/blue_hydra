require 'spec_helper'

describe PxRealtimeBluetooth do
  it "is a module" do
    expect(PxRealtimeBluetooth.class).to eq(Module)
  end

  it "has a version" do
    expect(PxRealtimeBluetooth::VERSION =~ /\d\.\d\.\d/i).to eq(0)
  end
end
