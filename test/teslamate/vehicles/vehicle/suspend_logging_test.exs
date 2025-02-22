defmodule TeslaMate.Vehicles.Vehicle.SuspendLoggingTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle

  alias TeslaMate.Vehicles.Vehicle

  test "immediately returns :ok if asleep", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "asleep"}}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :asleep}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

    assert :ok = Vehicle.suspend_logging(name)
    refute_receive _
  end

  test "immediately returns :ok if offline", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "offline"}}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :offline}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :offline}}}

    assert :ok = Vehicle.suspend_logging(name)
    refute_receive _
  end

  test "immediately returns :ok if already suspending", %{test: name} do
    events = [
      {:ok, online_event()}
    ]

    :ok = start_vehicle(name, events, settings: %{suspend_min: 1000})
    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}
    assert :ok = Vehicle.suspend_logging(name)

    refute_receive _
  end

  test "cannot be suspended if sleep mode is disabled", %{test: name} do
    events = [
      {:ok, online_event()}
    ]

    :ok = start_vehicle(name, events, settings: %{sleep_mode_enabled: false})
    assert_receive {:start_state, _, :online}

    assert {:error, :sleep_mode_disabled} = Vehicle.suspend_logging(name)
  end

  @tag :capture_log
  test "is suspended if sleep mode is disabled but enabled for current location", %{test: name} do
    events = [
      {:ok,
       online_event(drive_state: %{timestamp: 0, latitude: -50.606993, longitude: 165.972471})}
    ]

    :ok =
      start_vehicle(name, events,
        settings: %{sleep_mode_enabled: false},
        whitelist: [{-50.606993, 165.972471}]
      )

    assert_receive {:start_state, _, :online}

    assert :ok = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if sleep mode is disabled for the current location", %{test: name} do
    events = [
      {:ok,
       online_event(drive_state: %{timestamp: 0, latitude: -50.606993, longitude: 165.972471})}
    ]

    :ok = start_vehicle(name, events, blacklist: [{-50.606993, 165.972471}])
    assert_receive {:start_state, _, :online}

    assert {:error, :sleep_mode_disabled_at_location} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if vehicle is preconditioning", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: true}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :preconditioning} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if user is present", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{is_user_present: true}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :user_present} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if sentry mode is active", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: true}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :sentry_mode} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if vehicle is unlocked", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{locked: false}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events, settings: %{req_not_unlocked: true})
    assert_receive {:start_state, _, :online}

    assert {:error, :unlocked} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if shift_state is D", %{test: name} do
    not_supendable =
      online_event(drive_state: %{timestamp: 0, shift_state: "D", latitude: 0.0, longitude: 0.0})

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :vehicle_not_parked} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if shift_state is R", %{test: name} do
    not_supendable =
      online_event(drive_state: %{timestamp: 0, shift_state: "R", latitude: 0.0, longitude: 0.0})

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :vehicle_not_parked} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if shift_state is N", %{test: name} do
    not_supendable =
      online_event(drive_state: %{timestamp: 0, shift_state: "N", latitude: 0.0, longitude: 0.0})

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :vehicle_not_parked} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended while driving", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, drive_event(0, "D", 0)}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :vehicle_not_parked} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended while updating", %{test: name} do
    events = [
      {:ok, online_event()},
      {:ok, update_event("installing", "2019.8.4 530d1d3")}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}
    assert_receive {:start_update, _car_id}

    assert {:error, :update_in_progress} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended while charing is not complete", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, charging_event(0, "Charging", 1.5)}
    ]

    :ok = start_vehicle(name, events)
    assert_receive {:start_state, _, :online}

    assert {:error, :charging_in_progress} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if outside_temp is not nil", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{outside_temp: 20.0}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events, settings: %{req_no_temp_reading: true})
    assert_receive {:start_state, _, :online}

    assert {:error, :temp_reading} = Vehicle.suspend_logging(name)
  end

  test "cannot be suspended if inside_temp is not nil", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{inside_temp: 20.0}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    :ok = start_vehicle(name, events, settings: %{req_no_temp_reading: true})
    assert_receive {:start_state, _, :online}

    assert {:error, :temp_reading} = Vehicle.suspend_logging(name)
  end

  test "suspends when charging is complete", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, charging_event(0, "Charging", 1.5)},
      {:ok, charging_event(0, "Complete", 1.5)}
    ]

    :ok = start_vehicle(name, events, settings: %{suspend_min: 1_000_000})

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0},
                    []}

    assert_receive {:insert_charge, cproc, %{date: _, charge_energy_added: 1.5}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 1.5}}
    assert_receive {:complete_charging_process, ^cproc, []}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s3}}}
    assert DateTime.diff(s2, s3, :nanosecond) < 0

    refute_receive _
  end

  test "is suspendable when idling", %{test: name} do
    events = [
      {:ok, online_event()}
    ]

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: 100,
          suspend_min: 1000
        }
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    refute_receive _
  end

  test "detects if vehicle was locked", %{
    test: name
  } do
    unlocked =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{locked: false}
      )

    locked =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{locked: true}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, unlocked},
      {:ok, unlocked},
      {:ok, locked}
    ]

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: 100_000,
          suspend_min: 1000
        }
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}

    assert {:error, :unlocked} = Vehicle.suspend_logging(name)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{locked: false, state: :online}}}

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{locked: true, state: :suspended}}}

    refute_receive _
  end
end
