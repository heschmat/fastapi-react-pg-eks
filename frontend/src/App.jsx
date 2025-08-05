import { useEffect, useState } from 'react';
import axios from 'axios';
import './App.css';  // Import the CSS file

const API_URL = '/api';

function App() {
  const [form, setForm] = useState({ username: '', series_name: '', rating: 0 });
  const [recent, setRecent] = useState([]);
  const [stats, setStats] = useState(null);
  const [seriesQuery, setSeriesQuery] = useState('');

  const handleChange = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
  };

  const submitRating = async () => {
    const ratingValue = Number(form.rating);  // Convert to number

    if (!form.username || !form.series_name || isNaN(ratingValue) || ratingValue < 0 || ratingValue > 5) {
      alert('Please fill in all fields. Rating must be a number between 0 and 5.');
      return;
    }

    try {
      await axios.post(`${API_URL}/rate`, {
        ...form,
        rating: ratingValue,
      });
      setForm({ username: '', series_name: '', rating: 0 });
      fetchRecent();
    } catch (error) {
      console.error('Error submitting rating:', error);

      if (error.response && error.response.status === 422) {
        alert('Invalid data. Make sure your rating is a number between 0 and 5.');
      } else {
        alert('Something went wrong while submitting your rating. Please try again.');
      }
    }
  };


  const fetchRecent = async () => {
    const res = await axios.get(`${API_URL}/recent`);
    setRecent(res.data);
  };

  const fetchStats = async () => {
    if (!seriesQuery.trim()) {
      alert('Please enter a series name');
      return;
    }
    const res = await axios.get(`${API_URL}/series/${seriesQuery.toLowerCase()}/stats`);
    setStats(res.data);
  };

  useEffect(() => {
    fetchRecent();
  }, []);

  return (
    <div className="container">
      <section className="section">
        <h2 className="heading">Rate Your Favorite Series</h2>
        <input
          name="username"
          value={form.username}
          onChange={handleChange}
          placeholder="Your Username"
          className="input"
        />
        <input
          name="series_name"
          value={form.series_name}
          onChange={handleChange}
          placeholder="Series Name"
          className="input"
        />
        <input
          name="rating"
          type="number"
          min="0"
          max="5"
          value={form.rating}
          onChange={handleChange}
          className="input"
        />
        <button onClick={submitRating} className="button">Submit</button>
      </section>

      <section className="section">
        <h2 className="heading">Last 3 Ratings:</h2>
        <ul className="list">
          {recent.map((r, idx) => (
            <li key={idx} className="list-item">
              <strong>{r.username}</strong> rated <em>{r.series_name}</em> → <strong>{r.rating}/5</strong>
            </li>
          ))}
        </ul>
      </section>

      <section className="section">
        <h2 className="heading">Get Series Stats</h2>
        <input
          value={seriesQuery}
          onChange={(e) => setSeriesQuery(e.target.value)}
          placeholder="Series Name"
          className="input"
        />
        <button onClick={fetchStats} className="button">Fetch Stats</button>

        {stats && (
          <div className="stats-box">
            <p><strong>Series:</strong> {stats.series_name}</p>
            <p><strong>Ratings Count:</strong> {stats.num_ratings}</p>
            <p>
              <strong>Average:</strong>{" "}
              {stats.avg_rating !== null ? stats.avg_rating.toFixed(2) : "N/A"}
            </p>
          </div>
        )}
      </section>
    </div>
  );
}

export default App;
