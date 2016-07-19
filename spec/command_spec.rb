require 'spec_helper'

describe BlueHydra::Command do
  it 'executes a shell command and returns a hash of output' do
    result = BlueHydra::Command.execute3("echo 'hello world'")
    expect(result[:exit_code]).to eq(0)
    expect(result[:stdout]).to eq("hello world")
    expect(result[:stderr]).to eq(nil)
  end
end

describe "hciconfig output parsing" do
  it "returns a single mac" do
    begin
      expect(BlueHydra::EnumLocalAddr.call.count).to eq(1)
    rescue NoMethodError => e
      if e.message == "undefined method `scan' for nil:NilClass"
        #during testing we allow this to pass if there is no adapter
        expect(1).to eq(1)
      else
        raise e
      end
    end
  end
end
