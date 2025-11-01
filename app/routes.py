from .models import db  
from flask import Blueprint, render_template

main = Blueprint('main', __name__)

@main.route('/')
def index():
    return render_template('index.html')
@main.route('/klassement')
def klassement():
    return render_template('klassement.html')