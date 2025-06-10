package main

import "shared:svk"

Model_Instance :: struct {
	model:     ^svk.Model,
	blas:      ^Acceleration_Structure,
	transform: matrix[4, 4]f32,
}
