$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'generate_password.rb'

RSpec.describe GeneratePassword do
  context '.generate' do
    it 'generates password of correct length' do
      generated_password = GeneratePassword.generate(length: 16, charset: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()[]/\|=?+{}-')
      expect(generated_password.length).to eq(16)
    end
  end

  context '.no special chars' do
    it 'generates password - no special chars' do
      special_chars = '!$%^&*()[]\|=?+{}-'

      # generating 500 random passwords
      # they should alwayw pass: be 16 chars long and have no special chars
      (0..500).each do
        generated_password = GeneratePassword.generate(silent: true)
        expect(generated_password.length).to eq(16)

        special_chars.each_char do |special_char|
          # does not include special chars
          expect(generated_password).not_to include(special_char)

          # only letters (up/lower case) and numbers
          expect(generated_password[/[a-zA-Z0-9]+/]).to eq(generated_password)
        end
      end
    end
  end
end # RSpec.describe
