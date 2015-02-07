require 'spec_helper'

class Driver
  include RealtimeModel
  rt_attr :first_name,  as: String, index: true
  rt_attr :last_name,   as: String, index: true
  rt_attr :team,        as: String, index: true
end

class Car
  include RealtimeModel
  rt_attr :team,    as: String, index: true
  rt_attr :speed,   as: Float
  has_one :driver,  as: Driver # Driver must include RealtimeModel
end

class Race
  include RealtimeModel
  rt_attr   :name,  as: String
  rt_attr   :laps,  as: Integer
  has_many  :cars,  as: Car # Car must include RealtimeModel
end

describe RealtimeModel do

  describe '::new' do

    it 'creates a new object with attribute values matching the passed in hash' do
      car = Car.new(team: 'Ferrari', speed: 300.0)
      expect(car.team).to eq('Ferrari')
      expect(car.speed).to eq(300.0)
    end

    it "doesn't set attribute values when no hash is passed in" do
      car = Car.new
      expect(car.team).to be_nil
      expect(car.speed).to be_nil
    end

  end

  describe '::find' do

    it "returns nil if no object is found" do
      id = Car.send("highest_id").value + 1 # A car with this id hasn't been created
      car = Car.find id
      expect(car).to be_nil
    end

    it "returns the object with the matching id" do
      car0 = Car.new(team: 'Lotus')
      car1 = Car.find(car0.id)
      expect(car0.id).to eq(car1.id)
      expect(car0.team).to eq(car1.team)
    end

    it "returns the first object with a matching value for an indexed attribute" do
      team = SecureRandom.uuid
      Car.new(team: team)
      car = Car.find(team: team)
      expect(car.team).to eq(team)
    end

  end

  describe '::find_all' do

    it "returns all objects with matching values for indexed attribute" do
      team = SecureRandom.uuid
      1.upto(10) do
        Car.new(team: team)
      end
      cars = Car.find_all(team: team)
      expect(cars.size).to eq(10)
      cars.each do |car|
        expect(car.team).to eq(team)
      end
    end

  end

  describe '#<attribute>=' do

    it "updates the value of the attribute" do
      car = Car.new(team: 'Sauber')
      car.team = 'McLaren'
      expect(car.team).to eq('McLaren')
    end

  end

  describe '#delete' do

    it "deletes the object" do
      car = Car.new(team: 'Mercedes')
      car2 = Car.new(team: 'Williams')
      race = Race.new(name: 'Australian Grand Prix')
      race.cars << car2
      race.cars.remove(car2)
      car.delete
      car = Car.find(car.id)
      expect(car).to be_nil
    end

  end

  describe '#<has_many_assoc> <<' do

    it "adds an element to the collection's tail" do
      race = Race.new(name: 'Australian Grand Prix')
      expect(race.cars.size).to eq(0)
      race.cars << Car.new
      expect(race.cars.size).to eq(1)
      last_car = Car.new
      race.cars << last_car
      expect(race.cars.size).to eq(2)
      expect(race.cars[1].id).to eq(last_car.id)
    end

  end

  describe '#<has_many_assoc>.remove' do

    it "removes the element from the collection" do
      race = Race.new(name: 'German Grand Prix')
      car = Car.new(team: 'Red Bull Racing')
      race.cars << car
      race.cars.remove(car)
      expect(race.cars.size).to eq(0)
    end

  end

  describe '#<has_many_assoc>.remove_at' do

    it "removes the element at a specific position from the collection" do
      race = Race.new(name: 'Australian Grand Prix')
      car0 = Car.new(team: 'Force India')
      car1 = Car.new(team: 'Toro Rosso')
      race.cars << car0
      race.cars << car1
      race.cars.remove_at(0)
      expect(race.cars.size).to eq(1)
      expect(race.cars[0].id).to eq(car1.id)
    end

  end

  describe '#<has_one_assoc>.=' do

    it "sets the has_one assoc to the passed in object" do
      car = Car.new(team: 'Sauber')
      driver = Driver.new(first_name: 'Marcus', last_name: 'Ericsson', team: 'Sauber')
      car.driver = driver
      expect(car.driver.id).to eq(driver.id)
      car.driver = nil
      expect(car.driver).to be_nil
    end

  end

end