import os
import yaml
from flask import Flask, jsonify
from app.my_project import db, ma
from app.my_project.route import register_routes


def create_app(config_override=None):
    app = Flask(__name__)

    config_path = os.path.join(os.path.dirname(__file__), "app", "config", "app.yml")
    config = {}
    if os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}

    db_conf = config.get("database", {})
    user = db_conf.get("user", "root")
    password = db_conf.get("password", "")
    host = db_conf.get("host", "localhost")
    port = db_conf.get("port", 3306)
    db_name = db_conf.get("name", "flightradar_db")

    if password:
        uri = f"mysql+pymysql://{user}:{password}@{host}:{port}/{db_name}"
    else:
        uri = f"mysql+pymysql://{user}@{host}:{port}/{db_name}"

    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    if config_override:
        app.config.update(config_override)

    db.init_app(app)
    ma.init_app(app)

    register_routes(app)

    @app.route("/")
    def index():
        return jsonify({
            "message": "Welcome to Flightradar REST API",
            "status": "online",
            "endpoints": {
                "countries": "/api/countries",
                "types": "/api/types",
                "registration_infos": "/api/registration-infos",
                "roles": "/api/roles",
                "flight_routes": "/api/flight-routes",
                "waypoints": "/api/waypoints",
                "airports": "/api/airports",
                "airlines": "/api/airlines",
                "persons": "/api/persons",
                "aircrafts": "/api/aircrafts",
                "flights": "/api/flights",
                "crews": "/api/crews",
                "flight_waypoints": "/api/flight-waypoints",
                "special_1_to_m": "/api/countries/<country_id>/airports",
                "special_m_to_m_single": "/api/aircrafts/<aircraft_id>/crew",
                "special_m_to_m_all_aircrafts_with_crew": "/api/aircrafts/with-crew",
                "special_m_to_m_crews_by_aircraft": "/api/crews/grouped-by-aircraft",
                "special_m_to_m_crews_by_person": "/api/crews/grouped-by-person",
                "special_m_to_m_flights_by_waypoints": "/api/flight-waypoints/grouped-by-flight"
            }
        })

    return app


app = create_app()

if __name__ == "__main__":
    server_conf = {}
    config_path = os.path.join(os.path.dirname(__file__), "app", "config", "app.yml")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                yaml_data = yaml.safe_load(f) or {}
                server_conf = yaml_data.get("server", {})
        except Exception:
            pass

    host = server_conf.get("host", "127.0.0.1")
    port = server_conf.get("port", 5000)
    debug = server_conf.get("debug", True)

    app.run(host=host, port=port, debug=debug)
