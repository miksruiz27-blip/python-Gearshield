from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=True)
    role = Column(String, default="user")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    pdf_reports = relationship("PdfExport", back_populates="owner")

class PdfExport(Base):
    __tablename__ = "pdf_exports"

    id = Column(Integer, primary_key=True, index=True)
    report_uuid = Column(String, unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    filename = Column(String, nullable=False)
    pdf_path = Column(String, nullable=False)
    overall_risk_ai = Column(Float, default=0.0)
    is_synthetic = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="pdf_reports")

class BlacklistReport(Base):
    __tablename__ = "blacklist_reports"

    id = Column(Integer, primary_key=True, index=True)
    audio_path = Column(String, nullable=True)
    label = Column(String, nullable=True)
    overall_risk_ai = Column(Float, default=0.0)
    max_ai_prob = Column(Float, default=0.0)
    reporter_note = Column(String, nullable=True)
    reported_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
