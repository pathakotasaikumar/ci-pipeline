require 'component'
require 'runner'

class PricingTask
  def name
    "pricing"
  end

  def generate_pricing
    require "pricing/ec2"

    Log.info "Generating pricing file from latest pricing lists"

    Pricing::EC2.generate_pricing_file(
      file: Pricing::EC2::PRICING_FILE,
      term: "OnDemand",
      regions: ["Asia Pacific (Sydney)"]
    )
  end
end
