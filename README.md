RealtimeModel - Minimalist Redis Backed Object Modeling
=======================================================

RealtimeModel is a minimalist Persistant Object Model that uses Redis. It doesn't attempt to provide all of 
the magic of ActiveRecord, but it does support has_one and has_many relationships. The main difference between 
RealtimeModel and other Redis-backed ORM's is that RealtimeModel attribute values are persisted as soon as 
they are set -- there is no 'save' method. This is to preserve the atomicity that makes it useful to use
Redis for persistence in the first place. Every model has a version attribute that gets incremented whenever 
there's a change to one of its attributes or to the structure of one of its associations.

## Getting Started
In your Gemfile:

    gem "realtime_model"

Defining a model:

    class Race
    	include RealtimeModel
      rt_attr   :name,  as: String
      rt_attr   :laps,  as: Integer
      has_many  :cars', as: Car # Car must include RealtimeModel
    end

    class Car
      include RealtimeModel
      rt_attr :team,    as: String, index: true
      rt_attr :speed,   as: Float
      has_one :driver,  as: Driver # Driver must include RealtimeModel
    end

    class Driver
      include RealtimeModel
      rt_attr :first_name,  as: String, index: true
      rt_attr :last_name,   as: String, index: true
      rt_attr :team,        as: String, index: true
    end

## Creating

    race = Race.new(name: "Australian Grand Prix")

## Finding

Find by id
    car = Car.find(1)

Find using indexed attributes
    ferrari_driver = Driver.find(team: 'Ferrari')
    sauber_drivers = Driver.find_all(team: 'Sauber')

## Updating

With an instance

    car = Car.find(1)
    car.speed = 300.0 # no need to call car.save

## Deleting

    car = Car.find(1)
    car.delete

## Adding to a collection
    
    race.cars << car
    race.cars.insert(position, car)

## Moving items in a collection

    race.cars.move_to(position, item)

## Removing from a collection
  
    race.cars.remove(car)
    race.cars.remove_at(position)

## Requirements

    redis-objects