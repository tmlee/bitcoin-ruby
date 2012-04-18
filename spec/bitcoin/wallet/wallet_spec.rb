require_relative '../spec_helper'
require 'json'
include MiniTest
include Bitcoin
include Bitcoin::Wallet

def txout_mock(value, next_in = true, in_block = true)
  tx = Mock.new
  tx.expect(:get_block, in_block)
  txout = Mock.new
  txout.expect(:value, value)
  txout.expect(:get_next_in, next_in)
  txout.expect(:hash, [value, next_in].hash)
  txout.expect(:eql?, false, [1])
  txout.expect(:==, false, [1])
  txout.expect(:get_tx, tx)
end

describe Bitcoin::Wallet::Wallet do

  class DummyKeyStore

    def initialize keys
      @keys = keys.map{|k|{:key => k}}
    end

    def key(addr)
      @keys.select{|k|k[:key].addr==addr}.first
    end

    def keys
      @keys
    end

    def new_key
      k=Bitcoin::Key.generate
      @keys << {:key => k}
      @keys[-1]
    end
  end



  before do
    @storage = Mock.new
    @key = Key.from_base58('5J2hn1E8KEXmQn5gqykzKotyCcHbKrVbe8fjegsfVXRdv6wwon8')
    @addr = '1M89ZeWtmZmATzE3b6PHTBi8c7tGsg5xpo'
    @key2 = Key.from_base58('5KK9Lw8gtNd4kcaXQJmkwcmNy8Y5rLGm49RqhcYAb7qRhWxaWMJ')
    @addr2 = '134A4Bi8jN5V2KjkwmXUHjokDqdyqZ778J'
    @key3 = Key.from_base58('5JFcJByQvwYnWjQ2RHTTu6LLGiBj9oPQYsHqKWuKLDVAvv4cQ7E')
    @addr3 = '1EnrPVaRiRgrs1D7pujYZNN1N6iD9unZV6'
    keystore_data = [{:addr => @key.addr, :priv => @key.priv, :pub => @key.pub}]
    spec_dir = File.join(File.dirname(__FILE__), '../fixtures/wallet')
    FileUtils.mkdir_p(spec_dir)
    @filename = File.join(spec_dir, 'test1.json')
    File.open(@filename, 'w') {|f| f.write(keystore_data.to_json) }
    @keystore = SimpleKeyStore.new(file: @filename)
    @selector = MiniTest::Mock.new
    @wallet = Wallet.new(@storage, @keystore, @selector)
  end

  it "should get total balance" do
    @storage.expect(:get_txouts_for_address, [], [@addr])
    @wallet.get_balance.should == 0

    @storage.expect(:get_txouts_for_address, [txout_mock(5000, nil)], [@addr])
    @wallet.get_balance.should == 5000

    @storage.expect(:get_txouts_for_address, [txout_mock(5000, true), txout_mock(1000, nil)],
      [@addr])
    @wallet.get_balance.should == 1000
    @storage.verify
  end

  it "should get all addrs" do
    @wallet.addrs.should == [@addr]
    @wallet.addrs.size.should == 1
  end

  it "should list all addrs with balances" do
    @storage.expect(:get_balance, 0, ['dcbc93494b38ae96b14b1cc080d2acb514b7e955'])
    list = @wallet.list
    list.size.should == 1
    list = list[0]
    list.size.should == 2
    list[0][:addr].should == "1M89ZeWtmZmATzE3b6PHTBi8c7tGsg5xpo"
    list[1].should == 0

    @storage.expect(:get_balance, 5000, ['dcbc93494b38ae96b14b1cc080d2acb514b7e955'])
    list = @wallet.list
    list.size.should == 1
    list = list[0]
    list.size.should == 2
    list[0][:addr].should == @addr
    list[1].should == 5000
    @storage.verify
  end

  it "should create new addr" do
    @wallet.addrs.size.should == 1

    key = Key.generate
    a = @wallet.get_new_addr
    @wallet.addrs.size.should == 2
    @wallet.addrs[1].should == a
  end

  describe "Bitcoin::Wallet::Wallet#tx" do

    before do
      txout = txout_mock(5000, nil)
      tx = Mock.new
      tx.expect(:binary_hash, "foo")
      tx.expect(:out, [txout])
      tx.expect(:get_block, true)
      txout.expect(:get_tx, tx)
      txout.expect(:get_address, @addr)
      txout.expect(:pk_script,
        Script.to_address_script(@addr))
      @storage.expect(:get_txouts_for_address, [txout], [@addr])
      selector = Mock.new
      selector.expect(:select, [txout], [[txout]])
      @selector.expect(:new, selector, [[txout]])
      @tx = @wallet.tx([[:address, '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7', 1000]])
    end


    it "should have hash" do
      @tx.hash.size.should == 64
    end

    it "should have correct inputs" do
      @tx.in.size.should == 1
      @tx.in.first.prev_out.should == ("foo" + "\x00"*29)
      @tx.in.first.prev_out_index.should == 0
    end

    it "should have correct outputs" do
      @tx.out.size.should == 2
      @tx.out.first.value.should == 1000
      s = Script.new(@tx.out.first.pk_script)
      s.get_address.should == '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7'
    end

    it "should have change output" do
      @tx.out.last.value.should == 4000
      s = Script.new(@tx.out.last.pk_script)
      s.get_address.should == @addr
    end

    it "should leave tx fee" do
      @tx = @wallet.tx([[:address, '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7', 1000]], 50)
      @tx.out.last.value.should == 3950
    end

    it "should send change to specified address" do
      @tx = @wallet.tx([[:address, '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7', 1000]], 50,
        '1EAntvSjkNeaJJTBQeQcN1ieU2mYf4wU9p')
      Script.new(@tx.out.last.pk_script).get_address.should ==
        '1EAntvSjkNeaJJTBQeQcN1ieU2mYf4wU9p'
    end

    it "should send change to new address" do
      @tx = @wallet.tx([[:address, '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7', 1000]], 50, :new)
      @wallet.addrs.size.should == 2
      Script.new(@tx.out.last.pk_script).get_address.should == @wallet.addrs.last
    end

    it "should return nil if insufficient balance" do
      @tx = @wallet.tx([[:address, '1M2JjkX7KAgwMyyF5xc2sPSfE7mL1jqkE7', 7000]])
      @tx.should == nil
    end

  end

  describe "Bitcoin::Wallet::Wallet#tx (multisig)" do


    before do
      txout = txout_mock(5000, nil)
      tx = Mock.new
      tx.expect(:binary_hash, "foo")
      tx.expect(:out, [txout])
      tx.expect(:get_block, true)
      txout.expect(:get_tx, tx)
      txout.expect(:get_address, @addr)
      txout.expect(:pk_script, Script.to_address_script(@addr))
      @storage.expect(:get_txouts_for_address, [txout], [@addr])
      @keystore = DummyKeyStore.new([@key, @key2, @key3])

      selector = Mock.new
      selector.expect(:select, [txout], [1000])
      @selector.expect(:new, selector, [[txout]])
      @wallet = Wallet.new(@storage, @keystore, @selector)
      @tx = @wallet.tx([[:multisig, 1, @key2.addr, @key3.addr, 1000]])
    end

    it "should have correct outputs" do
      @tx.out.size.should == 2
      @tx.out.first.value.should == 1000
      s = Script.new(@tx.out.first.pk_script)
      s.get_addresses.should == [@addr2, @addr3]
    end

  end

end
