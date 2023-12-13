RSpec.shared_context "shared context" do
  # returns context description to context_description call
  let(:context_description) do |example|
    self.class.description
  end
end
