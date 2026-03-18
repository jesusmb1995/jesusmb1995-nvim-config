return {
  "sphamba/smear-cursor.nvim",
  opts = {
    cursor_color = "#ff6000",
    particles_enabled = true,
    never_draw_over_target = true,
    stiffness = 0.5,
    trailing_stiffness = 0.2,
    trailing_exponent = 5,
    damping = 0.6,
    particle_max_num = 100,
    particles_per_second = 200,
    particle_max_lifetime = 300,
    particle_gravity = -20,
    particle_random_velocity = 80,
    particle_spread = 0.5,
    gradient_exponent = 1.0,
    min_distance_emit_particles = 0,
  },
  event = "VeryLazy"
}
