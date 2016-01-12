require 'spec_helper'

describe BlueHydra::Command do
  it 'executes a shell command and returns a hash of output' do
    result = BlueHydra::Command.execute3("echo 'hello world'")
    expect(result[:exit_code]).to eq(0)
    expect(result[:stdout]).to eq("hello world")
    expect(result[:stderr]).to eq(nil)
  end
end

