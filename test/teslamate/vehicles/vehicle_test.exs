defmodule TeslaMate.Vehicles.VehicleTest do
  use TeslaMate.VehicleCase, async: true

  describe "starting" do
    @tag :capture_log
    test "handles unkown and faulty states", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "unknown"}},
        {:error, %TeslaApi.Error{message: "boom"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0, vehicle_id: 1001}, events)

      refute_receive _
    end

    test "handles online state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, vehicle_full(drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0})}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :online}

      refute_receive _
    end

    test "handles offline state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :offline}

      refute_receive _
    end

    test "handles asleep state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :asleep}

      refute_receive _
    end
  end

  describe "state" do
    alias TeslaMate.Vehicles.Vehicle

    test "returns the state :asleep", %{test: name} do
      events = [{:ok, %TeslaApi.Vehicle{state: "asleep"}}]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert :asleep = Vehicle.state(name)
    end

    test "returns the state :offline", %{test: name} do
      events = [{:ok, %TeslaApi.Vehicle{state: "offline"}}]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert :offline = Vehicle.state(name)
    end

    test "returns the state :online", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, vehicle_full(drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0})}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert :online = Vehicle.state(name)
    end

    test "returns the state :driving", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, drive_event(0, "R", 5)}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)
      assert_receive {:start_trip, _}

      assert :driving = Vehicle.state(name)
    end

    test "returns the state :charging", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, charging_event(0, "Charging", 0.1)}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)
      assert_receive {:start_charging_process, _, _}

      assert :charging = Vehicle.state(name)
    end

    test "returns the state :charging_complete", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, charging_event(0 + 1, "Complete", 0.1)}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)
      assert_receive {:start_charging_process, _, _}

      assert :charging_complete = Vehicle.state(name)
    end

    test "returns the state :suspended", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}}
      ]

      :ok =
        start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
          sudpend_after_idle_min: round(1 / 60),
          suspend_min: 1000
        )

      assert_receive {:start_state, 999, :online}
      refute_receive _, 50

      assert :suspended = Vehicle.state(name)
    end
  end

  describe "resume_logging/1" do
    alias TeslaMate.Vehicles.Vehicle

    test "leaves suspended and restores previous state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, charging_event(0, "Complete", 5.0)},
        {:ok, charging_event(0, "Complete", 5.0)},
        {:ok, charging_event(0, "Unplugged", 5.0)}
      ]

      :ok =
        start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
          sudpend_after_idle_min: round(1 / 60),
          suspend_min: 10_000
        )

      assert_receive {:start_state, _, :online}
      assert_receive {:start_charging_process, _, _}
      assert_receive {:insert_charge, _, %{charge_energy_added: 5.0}}

      refute_receive _, 50
      assert :suspended = Vehicle.state(name)

      assert :ok = Vehicle.resume_logging(name)

      assert :charging_complete = Vehicle.state(name)
      assert_receive {:close_charging_process, _}
      assert_receive {:start_state, _, :online}

      refute_receive _
    end
  end
end