class Config:
    SECRET_KEY = 'dev_key'
    SQLALCHEMY_DATABASE_URI = 'sqlite:///app.db'  # SQLite database in je projectmap
    SQLALCHEMY_TRACK_MODIFICATIONS = False
