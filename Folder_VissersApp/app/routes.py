from flask import Blueprint, request, redirect, url_for, render_template, session
from .models import db, User, Listing

main = Blueprint('main', __name__)

@main.route('/')
def index():
    return "Hello Flask!"
