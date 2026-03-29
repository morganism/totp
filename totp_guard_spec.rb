# frozen_string_literal: true
#
# spec/totp_guard_spec.rb
# RSpec test suite for the TOTPGuard 2FA library

require 'tmpdir'
require 'fileutils'
require_relative '../lib/totp_guard'

# ── Custom matchers ───────────────────────────────────────────────────────────

RSpec::Matchers.define :be_auth_success do
  match { |result| result.is_a?(TOTPGuard::AuthResult) && result.success? }
  failure_message { |r| "expected AuthResult to be successful, got: #{r}" }
end

RSpec::Matchers.define :be_auth_failure do
  match { |result| result.is_a?(TOTPGuard::AuthResult) && result.failure? }
  failure_message { |r| "expected AuthResult to be a failure, got: #{r}" }
end

# ── Shared contexts ───────────────────────────────────────────────────────────

shared_context 'with temp db' do
  let(:tmp_dir) { Dir.mktmpdir('totp_spec_') }
  let(:tmp_db)  { File.join(tmp_dir, 'totp.db') }

  after do
    store.close  rescue nil
    guard.close  rescue nil
    FileUtils.rm_rf(tmp_dir)
  end
end

shared_context 'with seeded store' do
  include_context 'with temp db'
  let(:account) { ACCOUNT }
  let(:secret)  { SECRET }
  before { store.add(account, secret) }
end

shared_examples 'a failed authentication' do |msg_fragment = nil|
  it 'returns an AuthResult' do
    expect(subject).to be_a(TOTPGuard::AuthResult)
  end

  it 'marks the result as failure' do
    expect(subject).to be_auth_failure
  end

  it "has a descriptive string including #{msg_fragment || 'DENIED'}" do
    expect(subject.to_s).to include(msg_fragment || 'DENIED')
  end
end

# ── Test vectors ─────────────────────────────────────────────────────────────
# RFC 6238 known-good secret; fixed time → deterministic code.

SECRET      = 'JBSWY3DPEHPK3PXP'
ACCOUNT     = 'spec:alice'
FIXED_TIME  = Time.at(1_700_000_000).freeze

# ── Core ─────────────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::Core do
  let(:valid_code) { described_class.totp(SECRET, time: FIXED_TIME) }

  describe '.generate_secret' do
    subject { described_class.generate_secret }

    it 'produces a Base32 string' do
      expect(subject).to match(/\A[A-Z2-7]+\z/)
    end

    it 'is at least 16 chars' do
      expect(subject.length).to be >= 16
    end

    it 'generates different secrets each call' do
      expect(described_class.generate_secret).not_to eq described_class.generate_secret
    end

    it 'respects a custom byte length' do
      short = described_class.generate_secret(10)
      expect(short.length).to be < subject.length
    end
  end

  describe '.totp' do
    it 'produces a 6-digit string' do
      expect(valid_code).to match(/\A\d{6}\z/)
    end

    it 'is deterministic for the same time' do
      expect(described_class.totp(SECRET, time: FIXED_TIME)).to eq valid_code
    end
  end

  describe '.validate' do
    it 'accepts the correct code' do
      expect(described_class.validate(SECRET, valid_code, time: FIXED_TIME)).to be true
    end

    it 'rejects a wrong code' do
      expect(described_class.validate(SECRET, '000000', time: FIXED_TIME)).to be false
    end

    it 'tolerates drift within the window' do
      drifted_time = Time.at(FIXED_TIME.to_i + 25)
      expect(described_class.validate(SECRET, valid_code, time: drifted_time, drift: 1)).to be true
    end

    it 'rejects code beyond drift window' do
      far_future = Time.at(FIXED_TIME.to_i + 120)
      expect(described_class.validate(SECRET, valid_code, time: far_future, drift: 1)).to be false
    end

    it 'handles string codes with whitespace' do
      expect(described_class.validate(SECRET, "  #{valid_code}  ", time: FIXED_TIME)).to be true
    end
  end

  describe 'DECODE_BASE32 constant lambda' do
    it 'is a frozen callable' do
      expect(described_class::DECODE_BASE32).to be_frozen
      expect(described_class::DECODE_BASE32).to respond_to(:call)
    end

    it 'raises on invalid characters' do
      expect { described_class::DECODE_BASE32.call('!@#$') }.to raise_error(ArgumentError)
    end
  end
end

# ── StringRefinements ─────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::StringRefinements do
  using TOTPGuard::StringRefinements

  describe 'String#base32?' do
    it { expect(SECRET.base32?).to be true }
    it { expect('JBSWY3DP'.base32?).to be false }  # too short
    it { expect('not-a-secret!!!'.base32?).to be false }
    it { expect('AAAAAAAAAAAAAAAAAA'.base32?).to be true }
    it { expect('aabbccdd11223344'.base32?).to be false }  # digits 1,3,8,9 invalid
  end

  describe 'String#account_key' do
    it { expect('github_morgan'.account_key).to eq 'github:morgan' }
    it { expect('aws_root'.account_key).to eq 'aws:root' }
    it { expect('simple'.account_key).to eq 'simple' }
    it { expect('a_b_c'.account_key).to eq 'a:b:c' }
  end
end

# ── AuthResult ────────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::AuthResult do
  let(:ok)  { described_class.new(ACCOUNT, true,  FIXED_TIME, 1, 6) }
  let(:bad) { described_class.new(ACCOUNT, false, FIXED_TIME, 1, 6) }

  describe 'immutability' do
    it 'is frozen on creation' do
      expect(ok).to be_frozen
    end

    it 'cannot be mutated' do
      expect { ok.account = 'hacker' }.to raise_error(FrozenError)
    end
  end

  describe '#success? / #failure?' do
    it { expect(ok.success?).to  be true  }
    it { expect(ok.failure?).to  be false }
    it { expect(bad.failure?).to be true  }
  end

  describe 'Comparable' do
    let(:older) { described_class.new(ACCOUNT, true, Time.at(0),            1, 6) }
    let(:newer) { described_class.new(ACCOUNT, true, Time.at(2_000_000_000), 1, 6) }

    it 'sorts by timestamp ascending' do
      expect([newer, older].sort).to eq [older, newer]
    end

    it 'older < newer' do
      expect(older).to be < newer
    end

    it 'supports between?' do
      mid = described_class.new(ACCOUNT, true, FIXED_TIME, 1, 6)
      expect(mid).to be_between(older, newer)
    end
  end

  describe 'pattern matching (deconstruct_keys)' do
    it 'supports hash pattern' do
      case ok
      in { account: String => a, success: true }
        expect(a).to eq ACCOUNT
      else
        raise 'pattern match failed'
      end
    end
  end

  describe '#to_s' do
    it 'includes AUTHENTICATED for success' do
      expect(ok.to_s).to include('AUTHENTICATED')
    end

    it 'includes DENIED for failure' do
      expect(bad.to_s).to include('DENIED')
    end

    it 'includes the account name' do
      expect(ok.to_s).to include(ACCOUNT)
    end
  end
end

# ── Store ─────────────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::Store do
  include_context 'with temp db'

  let(:store) { described_class.new(db_path: tmp_db) }

  describe '#add / #[]=' do
    it 'stores a secret' do
      store.add(ACCOUNT, SECRET)
      expect(store[ACCOUNT]).to eq SECRET
    end

    it 'accepts []= operator syntax' do
      store[ACCOUNT] = SECRET
      expect(store[ACCOUNT]).to eq SECRET
    end

    it 'raises ArgumentError for invalid Base32' do
      expect { store.add('bad:account', 'not-valid!!') }.to raise_error(ArgumentError, /Base32/)
    end

    it 'returns self for chaining' do
      result = store.add(ACCOUNT, SECRET)
      expect(result).to be store
    end

    it 'overwrites existing secret (INSERT OR REPLACE)' do
      new_secret = TOTPGuard::Core.generate_secret
      store.add(ACCOUNT, SECRET)
      store.add(ACCOUNT, new_secret)
      expect(store[ACCOUNT]).to eq new_secret
    end
  end

  describe '#delete' do
    before { store.add(ACCOUNT, SECRET) }

    it 'removes the account and returns true' do
      expect(store.delete(ACCOUNT)).to be true
      expect(store[ACCOUNT]).to be_nil
    end

    it 'returns false for a non-existent account' do
      expect(store.delete('ghost:account')).to be false
    end
  end

  describe '#exists?' do
    before { store.add(ACCOUNT, SECRET) }

    it { expect(store.exists?(ACCOUNT)).to  be true  }
    it { expect(store.exists?('ghost')).to be false }
  end

  describe '#account_for' do
    before { store.add(ACCOUNT, SECRET) }

    it 'reverses the lookup' do
      expect(store.account_for(SECRET)).to eq ACCOUNT
    end

    it 'returns nil for unknown secret' do
      expect(store.account_for('ZZZZZZZZZZZZZZZZ')).to be_nil
    end
  end

  describe '#search' do
    before do
      store.add('github:alice', SECRET)
      store.add('github:bob',   SECRET)
      store.add('aws:root',     SECRET)
    end

    it 'returns matching pairs' do
      results = store.search('github').map(&:first)
      expect(results).to contain_exactly('github:alice', 'github:bob')
    end

    it 'returns empty array for no matches' do
      expect(store.search('zzz_no_match')).to be_empty
    end
  end

  # ── Enumerable ───────────────────────────────────────────────────────────────

  describe 'Enumerable' do
    before do
      store.add('c:account', SECRET)
      store.add('a:account', SECRET)
      store.add('b:account', SECRET)
    end

    it '#count via Enumerable' do
      expect(store.count).to eq 3
    end

    it '#to_a returns all rows' do
      expect(store.to_a.map(&:first)).to contain_exactly('a:account', 'b:account', 'c:account')
    end

    it '#min returns lexically smallest entry' do
      expect(store.min[0]).to eq 'a:account'
    end

    it '#select filters rows' do
      matches = store.select { |account, _| account.start_with?('a') }
      expect(matches.map(&:first)).to eq ['a:account']
    end

    it '#map transforms rows' do
      keys = store.map(&:first)
      expect(keys).to all(be_a(String))
    end

    it '#each_account yields only names' do
      names = []
      store.each_account { |a| names << a }
      expect(names).to contain_exactly('a:account', 'b:account', 'c:account')
    end

    it '#each_account returns Enumerator without block' do
      expect(store.each_account).to be_an(Enumerator)
    end

    it '#each_with_hint redacts all but first 4 chars' do
      store.each_with_hint do |_account, hint|
        expect(hint).to match(/\A[A-Z2-7]{4}...\z/)
      end
    end
  end

  # ── method_missing ───────────────────────────────────────────────────────────

  describe 'method_missing / respond_to_missing?' do
    before { store.add('github:morgan', SECRET) }

    it 'looks up secret with underscore name' do
      expect(store.github_morgan).to eq SECRET
    end

    it '? variant returns true for existing account' do
      expect(store.github_morgan?).to be true
    end

    it '? variant returns false for missing account' do
      expect(store.no_such_account?).to be false
    end

    it '! variant returns the secret when found' do
      expect(store.github_morgan!).to eq SECRET
    end

    it '! variant raises KeyError when not found' do
      expect { store.totally_unknown! }.to raise_error(KeyError, /No TOTP account/)
    end

    it 'respond_to? is true for existing account methods' do
      expect(store).to respond_to(:github_morgan)
      expect(store).to respond_to(:github_morgan?)
      expect(store).to respond_to(:github_morgan!)
    end

    it 'respond_to? is false for missing account methods' do
      expect(store).not_to respond_to(:no_such_account_xyz)
    end
  end

  # ── ObjectSpace ──────────────────────────────────────────────────────────────

  describe '.live_count' do
    it 'tracks live Store instances' do
      before_count = described_class.live_count
      s2 = described_class.new(db_path: tmp_db)
      expect(described_class.live_count).to be >= before_count
      s2.close
    end
  end
end

# ── Authenticator ─────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::Authenticator do
  include_context 'with seeded store'

  let(:store)      { TOTPGuard::Store.new(db_path: tmp_db) }
  let(:guard)      { TOTPGuard::Guard.new(db_path: tmp_db) }
  let(:auth)       { described_class.new(store: store) }
  let(:valid_code) { TOTPGuard::Core.totp(SECRET, time: FIXED_TIME) }

  describe '#authenticate — value return' do
    subject { auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME) }

    it { is_expected.to be_auth_success }
    it { is_expected.to be_a(TOTPGuard::AuthResult) }
  end

  describe '#authenticate — block form' do
    it 'yields the AuthResult to the block' do
      auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME) do |r|
        expect(r).to be_auth_success
      end
    end

    it 'yields failure result for wrong code' do
      auth.authenticate(ACCOUNT, '000000', time: FIXED_TIME) do |r|
        expect(r).to be_auth_failure
      end
    end

    it 'yields the block return value as the method result' do
      result = auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME) { |r| r.success? ? :ok : :fail }
      expect(result).to eq :ok
    end
  end

  describe '#authenticate! (bang)' do
    it 'returns AuthResult on success' do
      result = auth.authenticate!(ACCOUNT, valid_code, time: FIXED_TIME)
      expect(result).to be_auth_success
    end

    it 'raises AuthenticationError on failure' do
      expect { auth.authenticate!(ACCOUNT, '000000') }
        .to raise_error(TOTPGuard::AuthenticationError, /2FA failed/)
    end
  end

  describe '#valid?' do
    it { expect(auth.valid?(ACCOUNT, valid_code, time: FIXED_TIME)).to be true  }
    it { expect(auth.valid?(ACCOUNT, '000000')).to                     be false }
    it { expect(auth.valid?('no:such', valid_code)).to                 be false }
  end

  describe 'on_success callback (Proc)' do
    it 'fires with the AuthResult' do
      received = nil
      auth.on_success { |r| received = r }
      auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)
      expect(received).to be_auth_success
    end

    it 'does not fire on failure' do
      fired = false
      auth.on_success { fired = true }
      auth.authenticate(ACCOUNT, '000000')
      expect(fired).to be false
    end
  end

  describe 'on_failure callback (Proc)' do
    it 'fires on wrong code' do
      fired = false
      auth.on_failure { fired = true }
      auth.authenticate(ACCOUNT, '000000')
      expect(fired).to be true
    end

    it 'does not fire on success' do
      fired = false
      auth.on_failure { fired = true }
      auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)
      expect(fired).to be false
    end
  end

  describe 'on_missing callback (Proc)' do
    it 'fires when account not in store' do
      fired = false
      auth.on_missing { fired = true }
      auth.authenticate('ghost:account', valid_code)
      expect(fired).to be true
    end
  end

  describe 'on_success is chainable (tap)' do
    it 'returns the authenticator for chaining' do
      result = auth.on_success { nil }
      expect(result).to be auth
    end
  end

  describe 'policy Lambda' do
    it 'blocks authentication when policy returns false' do
      auth.policy = ->(_) { false }
      expect(auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)).to be_auth_failure
    end

    it 'allows authentication when policy returns true' do
      auth.policy = ->(_) { true }
      expect(auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)).to be_auth_success
    end

    it 'can encode account-specific rules in the policy' do
      auth.policy = ->(acct) { acct != 'blocked:user' }
      expect(auth.authenticate('blocked:user', valid_code, time: FIXED_TIME)).to be_auth_failure
    end

    it 'rejects a non-callable policy' do
      expect { auth.policy = 'not callable' }.to raise_error(ArgumentError)
    end

    it 'accepts a Proc as policy (not just Lambda)' do
      auth.policy = proc { |_| true }
      expect(auth.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)).to be_auth_success
    end
  end
end

# ── Guard ─────────────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard::Guard do
  include_context 'with temp db'

  let(:store) { TOTPGuard::Store.new(db_path: tmp_db) }   # needed by shared context teardown
  let(:guard) { described_class.new(db_path: tmp_db) }
  let(:valid_code) { TOTPGuard::Core.totp(SECRET, time: FIXED_TIME) }

  before { guard.add(ACCOUNT, SECRET) }

  describe '#protect (block form)' do
    it 'yields true for a valid code' do
      yielded = nil
      guard.protect(ACCOUNT, valid_code, time: FIXED_TIME) { |ok| yielded = ok }
      expect(yielded).to be true
    end

    it 'yields false for an invalid code' do
      guard.protect(ACCOUNT, '000000') { |ok| expect(ok).to be false }
    end

    it 'returns AuthResult when no block given' do
      expect(guard.protect(ACCOUNT, valid_code, time: FIXED_TIME)).to be_a(TOTPGuard::AuthResult)
    end
  end

  describe '#provision (batch)' do
    it 'adds multiple accounts from a Hash' do
      guard.provision('batch:a' => SECRET, 'batch:b' => SECRET)
      expect(guard.exists?('batch:a')).to be true
      expect(guard.exists?('batch:b')).to be true
    end

    it 'returns self for chaining' do
      expect(guard.provision({})).to be guard
    end
  end

  describe '[] / []= operators' do
    it 'retrieves a secret via []' do
      expect(guard[ACCOUNT]).to eq SECRET
    end

    it 'adds via []=' do
      guard['new:account'] = SECRET
      expect(guard['new:account']).to eq SECRET
    end
  end

  describe '.instances via ObjectSpace' do
    it 'includes the current Guard in live instances' do
      expect(described_class.instances).to include(guard)
    end
  end

  describe 'Forwardable delegation' do
    it 'delegates #count to Store' do
      expect(guard.count).to eq 1
    end

    it 'delegates #exists? to Store' do
      expect(guard.exists?(ACCOUNT)).to be true
    end

    it 'delegates #drift to Authenticator' do
      expect(guard.drift).to eq 1
    end
  end
end

# ── TOTPGuard.new (module-level constructor) ──────────────────────────────────

RSpec.describe TOTPGuard, '.new' do
  let(:tmp_dir) { Dir.mktmpdir('totp_spec_') }
  let(:tmp_db)  { File.join(tmp_dir, 'totp.db') }

  after { FileUtils.rm_rf(tmp_dir) }

  it 'returns a Guard instance' do
    g = described_class.new(db_path: tmp_db)
    expect(g).to be_a(TOTPGuard::Guard)
    g.close
  end

  it 'yields the Guard to an optional block' do
    yielded = nil
    g = described_class.new(db_path: tmp_db) { |guard| yielded = guard }
    expect(yielded).to be g
    g.close
  end
end

# ── const_missing ─────────────────────────────────────────────────────────────

RSpec.describe TOTPGuard, 'const_missing' do
  it 'auto-provisions a named Guard for PascalCase constants' do
    g = TOTPGuard::SpecDummy
    expect(g).to be_a(TOTPGuard::Guard)
  end

  it 'returns the same instance on repeated access' do
    expect(TOTPGuard::SpecDummy).to be TOTPGuard::SpecDummy
  end

  it 'records the instance in named_guards' do
    _ = TOTPGuard::SpecDummy  # ensure it's provisioned
    expect(TOTPGuard.named_guards.keys).to include('SpecDummy')
  end

  it 'does not intercept ALL_CAPS constants (raises NameError)' do
    expect { TOTPGuard::TOTALLY_UNKNOWN_CONST }.to raise_error(NameError)
  end
end

# ── Integration ───────────────────────────────────────────────────────────────

RSpec.describe 'Integration: full 2FA lifecycle' do
  let(:tmp_dir)    { Dir.mktmpdir('totp_integration_') }
  let(:tmp_db)     { File.join(tmp_dir, 'totp.db') }
  let(:guard)      { TOTPGuard.new(db_path: tmp_db) }
  let(:valid_code) { TOTPGuard::Core.totp(SECRET, time: FIXED_TIME) }

  after  { guard.close; FileUtils.rm_rf(tmp_dir) }

  it 'full cycle: add → authenticate → delete' do
    guard.add(ACCOUNT, SECRET)

    result = guard.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)
    expect(result).to be_auth_success

    expect(guard.delete(ACCOUNT)).to be true
    expect(guard.exists?(ACCOUNT)).to be false
  end

  it 'provision → protect block → callback chain' do
    log = []
    guard.on_success { |r| log << "OK:#{r.account}" }
    guard.on_failure { |r| log << "FAIL:#{r.account}" }
    guard.provision(ACCOUNT => SECRET)

    guard.protect(ACCOUNT, valid_code, time: FIXED_TIME) { |ok| expect(ok).to be true }
    expect(log).to eq ["OK:#{ACCOUNT}"]
  end

  it 'method_missing lookup works end-to-end' do
    guard.add('github:morgan', SECRET)
    # Store is accessible via guard.instance_variable_get but let's test via the public API
    expect(guard.secret_for('github:morgan')).to eq SECRET
    expect(guard.exists?('github:morgan')).to be true
  end

  it 'AuthResult sorts across a real auth session' do
    guard.add(ACCOUNT, SECRET)
    results = [
      guard.authenticate(ACCOUNT, '000000', time: Time.at(100)),
      guard.authenticate(ACCOUNT, valid_code, time: FIXED_TIME),
    ]
    expect(results.sort.last).to be_auth_success
  end

  it 'policy lambda can enforce per-account rate limit simulation' do
    guard.add(ACCOUNT, SECRET)

    call_count = Hash.new(0)
    guard.policy = lambda { |acct|
      call_count[acct] += 1
      call_count[acct] <= 3   # allow at most 3 attempts
    }

    3.times { guard.authenticate(ACCOUNT, '000000') }

    blocked = guard.authenticate(ACCOUNT, valid_code, time: FIXED_TIME)
    expect(blocked).to be_auth_failure
  end
end
