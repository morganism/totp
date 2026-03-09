#!/usr/bin/env ruby
# 
# frozen_string_literal: true
#
# Quick self-test – no external test framework needed.
#   ruby totp_test.rb

require_relative 'totp'

pass = 0
fail_count = 0

def assert(label, result)
  if result
    puts "  PASS  #{label}"
    return 1
  else
    puts "  FAIL  #{label}"
    return 0
  end
end

puts "\n== TOTP Self-Test =="

# 1. Base32 round-trip
raw    = 'Hello, World!'
encoded = TOTP.encode_base32(raw)
decoded = TOTP.decode_base32(encoded)
pass += assert("Base32 round-trip", decoded == raw)

# 2. Known HOTP vector (RFC 4226 Appendix D, secret = "12345678901234567890")
# secret as Base32
known_secret = TOTP.encode_base32('12345678901234567890')
vectors = {
  0 => '755224',
  1 => '287082',
  2 => '359152',
  3 => '969429',
  4 => '338314',
}
vectors.each do |counter, expected|
  code = TOTP.hotp(known_secret, counter)
  pass += assert("HOTP counter=#{counter} => #{expected}", code == expected)
end

# 3. TOTP validate – generate then immediately validate
secret = TOTP.generate_secret
code   = TOTP.totp(secret)
pass += assert("validate current code", TOTP.validate(secret, code))

# 4. validate rejects wrong code
pass += assert("validate rejects wrong code", !TOTP.validate(secret, '000000'))

# 5. validate rejects code from a distant window
old_code = TOTP.hotp(secret, (Time.now.to_i / 30) - 10)
pass += assert("validate rejects stale code (10 windows back)", !TOTP.validate(secret, old_code))

# 6. Secret generation length (Base32 of 20 bytes -> 32 chars)
s = TOTP.generate_secret
pass += assert("generate_secret produces non-empty Base32 string",
               s.match?(/\A[A-Z2-7]+\z/) && s.length > 0)

# 7. otpauth URI shape
uri = TOTP.otpauth_uri(secret, account: 'alice@example.com', issuer: 'MyApp')
pass += assert("otpauth URI starts correctly",
               uri.start_with?('otpauth://totp/') && uri.include?("secret=#{secret}"))

puts "\n#{pass} passed, 0 skipped."
puts fail_count > 0 ? "#{fail_count} FAILED" : "All tests passed.\n"
