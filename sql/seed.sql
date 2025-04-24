INSERT INTO users (username, email) VALUES
('john_doe', 'john@example.com'),
('jane_smith', 'jane@example.com');

INSERT INTO products (name, price, stock) VALUES
('Laptop', 999.99, 10),
('Smartphone', 499.99, 20);

INSERT INTO orders (user_id, total_amount) VALUES
(1, 999.99),
(2, 499.99);

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 999.99),
(2, 2, 1, 499.99);

INSERT INTO reviews (user_id, product_id, rating, comment) VALUES
(1, 1, 5, 'Great laptop!'),
(2, 2, 4, 'Good phone, but battery could be better.');