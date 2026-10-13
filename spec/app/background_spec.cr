require "../spec_helper"

describe "App#every and App#on_stop" do
  it "rejects an interval that is not positive" do
    app = Alumna::App.new
    expect_raises(ArgumentError, "interval must be > 0") do
      app.every(Time::Span.zero) { }
    end
    expect_raises(ArgumentError, "interval must be > 0") do
      app.every(-1.milliseconds) { }
    end
  end

  it "runs the block until close, then does not start another pass" do
    app = Alumna::App.new
    count = Atomic(Int32).new(0)
    app.every(5.milliseconds) do
      count.add(1)
    end

    deadline = Time.instant + 2.seconds
    while count.get == 0 && Time.instant < deadline
      sleep 1.millisecond
    end
    if count.get == 0
      app.close
      fail "every did not run"
    end

    app.close
    seen = count.get
    sleep 40.milliseconds
    count.get.should eq(seen)
  end

  it "runs stop hooks once, in order, and close without hooks still returns" do
    plain = Alumna::App.new
    plain.close

    app = Alumna::App.new
    order = [] of Int32
    app.on_stop { order << 1 }
    app.on_stop { order << 2 }
    app.close
    app.close
    order.should eq([1, 2])
  end
end
