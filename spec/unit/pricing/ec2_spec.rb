$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/pricing"))
require 'ec2'

RSpec.describe Pricing::EC2 do
  context '.price' do
    it 'returns price for Windows instance' do
      price = Pricing::EC2.price(
        instance_type: "c3.large",
        operating_system: "windows",
        license: "no license required",
        tenancy: "shared",
        software: "na"
      )

      Log.debug price
      expect(price).to eq 0.238
    end
    it 'returns price for c3.large Linux instance' do
      price = Pricing::EC2.price(
        instance_type: "c3.large",
        operating_system: "linux",
        license: "no license required",
        tenancy: "shared",
        software: "na"
      )
      expect(price).to eq 0.132
    end

    it 'returns price for c4.large Linux instance' do
      price = Pricing::EC2.price(
        instance_type: "c4.large",
        operating_system: "linux",
        license: "no license required",
        tenancy: "shared",
        software: "na"
      )
      expect(price).to eq 0.13
    end

    it 'returns price for c5.large Linux instance' do
      price = Pricing::EC2.price(
        instance_type: "c5.large",
        operating_system: "linux",
        license: "no license required",
        tenancy: "shared",
        software: "na"
      )
      expect(price).to eq 0.111
    end

    it 'returns price for RedHat instance' do
      price = Pricing::EC2.price(
        instance_type: "m4.large",
        operating_system: "rhel",
        license: nil,
        tenancy: "shared",
        software: nil
      )
      expect(price).to eq 0.185
    end

    it 'does not returns price for an unknown OS' do
      price = Pricing::EC2.price(
        instance_type: "m4.large",
        operating_system: "Unknown",
        license: "no license required",
        tenancy: "shared",
        software: "NA"
      )
      expect(price.nil?).to eq true
    end
  end

  context '._get_spot_price_os' do
    it 'returns values' do
      expect(Pricing::EC2.send(:_get_spot_price_os, platform: :windows)).to eq('windows')
      expect(Pricing::EC2.send(:_get_spot_price_os, platform: :amazon_linux)).to eq('linux')
      expect(Pricing::EC2.send(:_get_spot_price_os, platform: :centos)).to eq('linux')
      expect(Pricing::EC2.send(:_get_spot_price_os, platform: :rhel)).to eq('rhel')
      expect { Pricing::EC2.send(:_get_spot_price_os, platform: :blah) }.to raise_error(/Unsupported platform value/)
    end
  end

  context '.process_ec2_spot_price' do
    it 'does not set :rhel, t2.|hs1 sizes' do
      values = [
        {
          :resource => {},
          :spot_alias => "@ondemand",
          :platform => :amazon_linux,
          :instance_type => "t2.micro",
          :tenancy => nil
        },
        {
          :resource => {},
          :spot_alias => "@ondemand",
          :platform => :amazon_linux,
          :instance_type => "hs1.micro",
          :tenancy => nil
        },
        {
          :resource => {},
          :spot_alias => "@ondemand",
          :platform => :rhel,
          :instance_type => "m4.large",
          :tenancy => nil
        }
      ]

      values.each do |value|
        spot_bid = Pricing::EC2.process_ec2_spot_price(
          spot_alias: value[:spot_alias],
          platform: value[:platform],
          instance_type: value[:instance_type],
          tenancy: value[:tenancy]
        )

        expect(spot_bid).to be(nil)
      end
    end

    it 'sets values for :amazon_linux, :centos, :rhel, :windows' do
      input = [
        {
          :spot_alias => "@ondemand",
          :platform => :amazon_linux,
          :instance_type => "m4.large",
          :tenancy => nil
        },
        {
          :spot_alias => "@ondemand",
          :platform => :centos,
          :instance_type => "m4.large",
          :tenancy => nil
        },
        {
          :spot_alias => "@ondemand",
          :platform => :rhel,
          :instance_type => "m4.large",
          :tenancy => nil
        },
        {
          :spot_alias => "@ondemand",
          :platform => :windows,
          :instance_type => "m4.large",
          :tenancy => nil
        }
      ]

      output = [0.125, 0.125, nil, 0.217]

      input.each_with_index do |value, index|
        spot_bid = Pricing::EC2.process_ec2_spot_price(
          spot_alias: value[:spot_alias],
          platform: value[:platform],
          instance_type: value[:instance_type],
          tenancy: value[:tenancy]
        )

        expect(spot_bid).to be(output[index])
      end
    end
  end
end # RSpec.describe
