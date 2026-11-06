import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mean, stdev, covariance, correlation, percentile, inverseNormal,
  cholesky, matrixVector, projectToSimplex, sum, SeededRandom, fnv1a,
} from '../js/core/math.js';

test('mean and sample standard deviation', () => {
  assert.equal(mean([1, 2, 3, 4]), 2.5);
  assert.equal(mean([]), 0);
  assert.ok(Math.abs(stdev([2, 4, 4, 4, 5, 5, 7, 9]) - 2.138089935299395) < 1e-12);
});

test('covariance and correlation', () => {
  const a = [1, 2, 3, 4, 5];
  const b = [2, 4, 6, 8, 10];
  assert.ok(Math.abs(covariance(a, b) - 5) < 1e-12);
  assert.ok(Math.abs(correlation(a, b) - 1) < 1e-12);
  assert.ok(Math.abs(correlation(a, a.map((v) => -v)) + 1) < 1e-12);
});

test('percentile interpolates', () => {
  assert.equal(percentile([1, 2, 3, 4, 5], 0.5), 3);
  assert.equal(percentile([1, 2, 3, 4, 5], 0), 1);
  assert.equal(percentile([1, 2, 3, 4, 5], 1), 5);
  assert.ok(Math.abs(percentile([0, 10], 0.25) - 2.5) < 1e-12);
});

test('inverse normal matches known quantiles', () => {
  assert.ok(Math.abs(inverseNormal(0.5)) < 1e-9);
  assert.ok(Math.abs(inverseNormal(0.975) - 1.959963984540054) < 1e-6);
  assert.ok(Math.abs(inverseNormal(0.025) + 1.959963984540054) < 1e-6);
});

test('cholesky reconstructs the matrix', () => {
  const matrix = [[4, 2, 0.6], [2, 5, 1], [0.6, 1, 3]];
  const lower = cholesky(matrix);
  assert.ok(lower);
  const reconstructed = lower.map((row, i) => lower.map((_, j) => {
    let total = 0;
    for (let k = 0; k < lower.length; k += 1) total += lower[i][k] * lower[j][k];
    return total;
  }));
  reconstructed.forEach((row, i) => row.forEach((value, j) => {
    assert.ok(Math.abs(value - matrix[i][j]) < 1e-10);
  }));
});

test('cholesky rejects non-positive-definite matrices', () => {
  assert.equal(cholesky([[1, 2], [2, 1]]), null);
});

test('matrix vector multiplication', () => {
  assert.deepEqual(matrixVector([[1, 2], [3, 4]], [5, 6]), [17, 39]);
});

test('projection satisfies simplex and weight cap', () => {
  const weights = projectToSimplex([0.9, 0.9, -0.2, 0.1], 0.5);
  assert.ok(Math.abs(sum(weights) - 1) < 1e-9);
  weights.forEach((w) => assert.ok(w >= -1e-12 && w <= 0.5 + 1e-9));
});

test('seeded random is reproducible', () => {
  const a = new SeededRandom(123n);
  const b = new SeededRandom(123n);
  const left = Array.from({ length: 8 }, () => a.next());
  const right = Array.from({ length: 8 }, () => b.next());
  assert.deepEqual(left, right);
  left.forEach((v) => assert.ok(v >= 0 && v < 1));
});

test('fnv1a hashes are stable', () => {
  assert.equal(fnv1a('SPY'), fnv1a('SPY'));
  assert.notEqual(fnv1a('SPY'), fnv1a('QQQ'));
});
