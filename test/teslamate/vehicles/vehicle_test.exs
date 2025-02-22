defmodule TeslaMate.Vehicles.VehicleTest do
  use TeslaMate.VehicleCase, async: true

  describe "starting" do
    @tag :capture_log
    test "handles unkown and faulty states", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "unknown"}},
        {:error, %TeslaApi.Error{message: "boom"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :unavailable, healthy: true}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{healthy: false, state: :unavailable}}}

      refute_receive _
    end

    test "handles online state", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "handles offline state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :offline}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      refute_receive _
    end

    test "handles asleep state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :asleep}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      refute_receive _
    end
  end

  describe "resume_logging/1" do
    alias TeslaMate.Vehicles.Vehicle

    test "does nothing of already online", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online}, 100
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert :ok = Vehicle.resume_logging(name)

      refute_receive _
    end

    test "increases polling frequency if asleep", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :asleep}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      assert :ok = Vehicle.resume_logging(name)

      assert_receive {:start_state, ^car, :online}, 100
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "increases polling frequency if offline", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :offline}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      assert :ok = Vehicle.resume_logging(name)

      assert_receive {:start_state, ^car, :online}, 100
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end

  describe "settings change" do
    alias TeslaMate.Vehicles.Vehicle
    alias TeslaMate.Settings.CarSettings

    test "applies new sleep settings", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok =
        start_vehicle(name, events,
          suspend_after_idle_min: 999_999_999,
          suspend_min: 10_000
        )

      # Online
      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      refute_receive _, 500

      # Reduce suspend_after_idle_min
      send(name, %CarSettings{suspend_after_idle_min: 1, suspend_min: 10_000})
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      refute_receive _
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "restarts if the eid changed", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :vehicle_not_found}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      # Too many errors
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: false}}}

      # Killed
      assert_receive {VehiclesMock, :kill}
    end

    @tag :capture_log
    test "reports the health status", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :unknown}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      # ...

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: false}}}, 1000
    end

    @tag :capture_log
    test "handles timeout errors", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :timeout},
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :closed},
        {:error, :closed},
        {:error, :timeout},
        {:ok, online_event()},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      refute_receive _, 100
    end

    @tag :capture_log
    test "notices if vehicle is in service ", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :in_service},
        {:error, :in_service},
        {:error, :in_service},
        {:error, :in_service},
        {:error, :in_service},
        {:ok, online_event()},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      refute_receive _, 400
    end

    @tag :capture_log
    test "stops polling if signed out", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :not_signed_in},
        # next events shall just show that polling stops
        {:ok, online_event()},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :start, healthy: false}}}

      refute_receive _
    end
  end

  describe "summary" do
    test "returns the summary if no api request was completed yet", %{test: name} do
      events = [
        fn ->
          Process.sleep(10_000)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicle(name, events)

      for _ <- 1..10 do
        assert %Vehicle.Summary{state: :unavailable, healthy: true} = Vehicle.summary(name)
      end
    end

    test "returns the summary even if the api call is blocked", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        fn ->
          Process.sleep(10_000)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online}

      for _ <- 1..10 do
        assert %Vehicle.Summary{state: :online, healthy: true} = Vehicle.summary(name)
      end
    end
  end
end
